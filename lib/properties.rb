require "properties/engine"

module Properties

  delegate :all_by_property_name_for, :all_by_property_id_for, :convert_string_value,
    :validate_value_against_type, to: :PropertyDefinition

  def self.included(base)
    base.instance_variable_set('@property_owner', base.name.underscore.upcase) # e.g. "ORDER_LINE"
    base.instance_variable_set('@property_class', base.const_get(base.name + 'Property')) # e.g. OrderLineProperty
    base.extend ClassMethods

    # delegate instance methods to class
    base.delegate :property_owner, :property_class, :implicit_properties,
      :determine_action, :get_property_id_from, to: base.name.to_sym

    base.has_many "#{base.name.underscore}_properties".to_sym,
      -> { order(:property_id, :seq_no) }, inverse_of: "#{base.name.underscore}"

    class << base
      attr_reader :property_owner, :property_class

      # delegate class methods to PropertyDefinition class
      delegate :all_by_property_id_for, :all_by_property_name_for, :convert_string_value,
        :validate_value_against_type, to: :PropertyDefinition
    end

    base.define_property_methods
  end

  module ClassMethods

    def define_property_methods
      PropertyDefinition.clear_caches

      implicit_properties.keys.each do |property_name|
        define_method property_name do
          cached_properties[property_name]
        end
      end
    end

    def implicit_properties(property_names=[])
      property_names = [*property_names] unless property_names.is_a?(Array)
      out = all_by_property_id_for(property_owner).reduce({}) do |hash, (_, property_attributes)|
        property_sym = property_attributes[:property_name].to_sym
        if property_names.empty? || property_names.include?(property_sym)
          hash.merge(property_sym =>
            convert_string_value(property_attributes[:default_value], property_attributes[:property_type]))
        else
          hash
        end
      end
      unless property_names.empty? || out.size == property_names.size
        raise "Unknown properties: #{property_names - out.keys}"
      end
      out
    end

    def get_property_id_from(property_name)
      all_by_property_name_for(property_owner)[property_name.to_s][:property_id]
    end

    def determine_action(explicit, implicit, input_property_name, input_property_value)
      raise "Unknown property: #{input_property_name}" unless implicit.keys.include? input_property_name
      if explicit.has_key? input_property_name
        if eq?(explicit[input_property_name], input_property_value)
          if eq?(implicit[input_property_name], input_property_value)
            # input property name & value matches existing explicit *and* implicit default value
            # which means that explicit property is redundant and we should delete it
            :delete
          else
            # nothing to do, input property name & value matches existing explicit one
            # but *not* the default value of the implicit one
            :none
          end
        else
          # input property value is different than existing explicit one
          if eq?(implicit[input_property_name], input_property_value)
            # input property value matches default value of existing
            # implicit property so we delete the explicit property
            :delete
          else
            # input property value is different from both explicit value
            # and implicit default value, so we update the explicit property
            :update
          end
        end
      else
        # there's no explicit property with this input name
        if eq?(implicit[input_property_name], input_property_value)
          # nothing to do, input property value matches default value of existing
          # implicit property
          :none
        else
          # input property value is different from implicit default value
          # so we insert an explicit property with a value
          :insert
        end
      end
    end

    def eq?(a, b)
      (a.class == b.class) && (a.is_a?(Float) ? (a - b).abs <= 1e-14 : a == b)
    end

  end # end of class methods

  # original design notes:
  #
  # input is an optional set of property names
  # if the set is empty, all properties (implicit and explicit) are retrieved
  # the output is a hash of property_name => converted value, with values that
  # have been hydrated for implicit property defaults
  def properties(property_names=[])
    property_names = [*property_names] unless property_names.is_a?(Array)
    implicit = implicit_properties(property_names)
    explicit = explicit_properties(property_names)
    implicit.merge(explicit)
  end

  def cached_properties
    @all_properties ||= properties
  end

  def explicit_properties(property_names=[])
    property_names = [*property_names] unless property_names.is_a?(Array)
    method_name = "#{property_owner.underscore}_properties" # activerecord relation
    if property_names.empty?
      send(method_name)
    else
      unknown = []
      property_ids = property_names.map do |property_name|
        property_attributes = all_by_property_name_for(property_owner)[property_name.to_s]
        (unknown << property_name; next) unless property_attributes
        property_attributes[:property_id]
      end
      raise "Unknown properties: #{unknown}" unless unknown.empty?
      send(method_name).where(property_id: property_ids)
    end.reduce({}) do |hash, property|
      property_attributes = all_by_property_id_for(property_owner)[property.property_id]
      # TODO instead of allowing this inconsistency to happen, use a monitor synchronized
      # block to ensure atomicity between earlier call to all_by_property_name_for and
      # this call to all_by_property_id_for
      raise "in-memory property not found for property id #{property.property_id}" unless property_attributes
      property_sym = property_attributes[:property_name].to_sym
      if property.seq_no > 0
        value = hash[property_sym]
        value = [value] unless value.is_a?(Array)
        value << convert_string_value(property.property_value, property_attributes[:property_type])
        hash.merge(property_sym => value)
      else
        hash.merge(property_sym =>
          convert_string_value(property.property_value, property_attributes[:property_type]))
      end
    end
  end

  # original design notes:
  #
  # save an input hash of properties to the corresponding *_properties table
  # for this model instance; this method will effectively insert, update,
  # and/or delete properties
  #
  # Approach 1: Atomic assignment of a property set for a given record,
  # read all existing db properties for this record into mem, perform set difference,
  # update accordingly including deletions. 3 possible outcomes: deleted property,
  # inserted new, or updated existing. Perform actions in bulk, e.g. delete all
  # that should be deleted, use batch create and update
  #
  # Approach 2: Delete all existing db properties for this record, then insert all
  # input properties. Much easier to implement but harder on db, since most of the
  # time existing data won't change. Also potentially result in table fragmentation
  # in the db and slowdown (DELETE followed by INSERT vs. UPDATE in approach 1)
  #
  # for each entry in the input hash, do the following:
  # 1. Verify the key is a valid property name
  # 2. Verify the value is compatible with expected type
  # 3. If there is a default and the value equals to the default remove the entry
  # otherwise add to the output payload going into the db
  def properties=(input_properties_hash={})

    # TODO make thread-safe via monitor.synchronized block
    # currently, calls to PropertyDefinition.all_by_* could become inconsistent
    # with each other e.g. another thread calls clear_caches in the midst of
    # execution of this method, say, between implicit and explicit retrieval

    actions = { insert: [], update: [], delete: [] }
    implicit = implicit_properties(input_properties_hash.keys)
    explicit = explicit_properties

    input_properties_hash.each do |input_property_name, input_property_value|
      action = determine_action(explicit, implicit, input_property_name, input_property_value)
      case action
        when :none
          next
        when :delete
          actions[action] << get_property_id_from(input_property_name)
        when :insert, :update
          actions[action] += validate_and_pack(input_property_name, input_property_value)
      end
    end
    actions[:delete] += (explicit.keys - input_properties_hash.keys).map do |input_property_name|
      get_property_id_from(input_property_name)
    end

    Rails.logger.debug actions
    persist_actions(actions)
    true
  end

  def persist_actions(actions)
    ActiveRecord::Base.transaction do
      fk = "#{property_owner.underscore}_id".to_sym
      property_class
        .where(property_id: actions[:delete], fk => id)
        .delete_all unless actions[:delete].empty?
      Upsert.batch(property_class.connection, property_class.table_name) do |upsert|
        f = -> hash { upsert.row(hash[:selector], hash[:setter]) }
        actions[:insert].each &f
        actions[:update].each &f
        association("#{property_owner.underscore}_properties".to_sym).reload
      end
    end
  end

  def validate_and_pack(property_name, property_value)
    all_by_property_name = all_by_property_name_for(property_owner)
    raise "Unknown property: #{property_name}" unless all_by_property_name.keys.include? property_name.to_s
    property_attributes = all_by_property_name[property_name.to_s]
    property_type = property_attributes[:property_type]
    default_value = property_attributes[:default_value]
    if property_value.is_a?(Array)
      if default_value
        raise "Unsupported sequence property (#{property_name}) with non-nil default value (#{default_value})"
      end
    else
      property_value = [property_value]
    end
    fk = "#{property_owner.underscore}_id".to_sym
    property_value.map.with_index do |value, index|
      validate_value_against_type(value, property_type)
      {
        selector: {
          fk => id,
          property_id: property_attributes[:property_id],
          seq_no: index
        },
        setter: {
          property_value: value
        }
      }
    end
  end

end
