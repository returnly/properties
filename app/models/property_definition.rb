# == Schema Information
#
# Table name: property_definitions
#
#  property_id    :integer          not null, primary key
#  property_owner :string(50)       not null
#  property_name  :string(50)       not null
#  property_type  :string(9)        default("STRING"), not null
#  default_value  :string(512)
#  description    :string(100)
#  created_at     :datetime         default(NULL), not null
#  updated_at     :datetime
#
# Indexes
#
#  property_owner  (property_owner,property_name) UNIQUE
#

class PropertyDefinition < ActiveRecord::Base
  self.primary_key = 'property_id'

  after_save { self.class.clear_caches }
  validate :default_value_consistent_with_type

  def default_value_consistent_with_type
    self.class.convert_string_value(default_value, property_type)
  rescue => e
    errors.add(e.message =~ /unknown property type/i ? :property_type : :default_value, e.message)
  end

  PROPERTY_TYPES = %w(INT FLOAT BOOL STRING DATE TIMESTAMP)

  class << self

    # used in clear_caches method
    # keeps track of all memory caches that get set
    attr_reader :cache_names

    %i(
        property_id
        property_name
      ).each do |index_field|

      # build a cache in memory as
      # { some_property_attribute => { remaining property attributes } }
      #
      # e.g. property_id as index field:
      # 58 => {
      #   :property_name  => "interface812",
      #   :property_owner => "ORDER_LINE"
      #   :property_type  => "STRING",
      #   :default_value  => "tofu"
      # }
      method_name = "all_by_#{index_field}_for"
      define_method method_name do |property_owner|
        field_name = "@#{method_name}_#{property_owner.underscore}"
        field_value = instance_variable_get(field_name)
        return field_value if field_value
        (@cache_names ||= []) << field_name
        attr_names = %i(property_id property_name property_owner property_type default_value)
        instance_variable_set(field_name, begin # <-- atomic and thread-safe assignment
          where(property_owner: property_owner)
            .reduce({}) do |hash, attr|
            h = Hash[attr_names.zip attr[attr_names]]
            hash.merge(h[index_field] => h.except(index_field))
          end
        end)
      end

      # this method will force reload of all
      # owner-specific property definitions from the db
      define_method (method_name + "!") do |property_owner|
        clear_caches
        send(method_name, property_owner)
      end

      %w(
          with_default
          without_default
        ).each do |wdef|

        # restrict the view of the owner-specific cache to contain
        # only properties with/without a default value
        wdef_method_name = "all_by_#{index_field}_#{wdef}_for"
        define_method wdef_method_name do |property_owner|
          field_name = "@#{wdef_method_name}_#{property_owner.underscore}"
          field_value = instance_variable_get(field_name)
          return field_value if field_value
          (@cache_names ||= []) << field_name
          instance_variable_set(field_name, begin
            send(method_name, property_owner).select do |_, v|
              wdef.include?("without") ? v[:default_value].nil? : !v[:default_value].nil?
            end
          end)
        end

        # similar to the above, force reload of all properties from db
        define_method (wdef_method_name + "!") do |property_owner|
          clear_caches
          send(wdef_method_name, property_owner)
        end

      end # with/without

    end # id/name

    def clear_caches
      return unless cache_names
      cache_names.each do |cache_name|
        instance_variable_set(cache_name, nil) # <-- atomic and thread-safe assignment
      end
    end

    # Going into the db, this method checks that the ruby data type of the input property value
    # is consistent with the logical property type:
    # (Fixnum, Float, TrueClass, FalseClass, String, Date, DateTime) <-->
    #     (INT, FLOAT, BOOL, STRING, DATE, TIMESTAMP)
    #
    # We want to perform this validation before we subsequently use ActiveRecord to
    # seamlessly convert from the ruby data types into mysql VARCHAR going into the db:
    # (Fixnum, Float, TrueClass, FalseClass, String, Date, DateTime) --> [ActiveRecord] --> mysql VARCHAR
    #
    def validate_value_against_type(property_value, property_type)
      return if property_value.nil?
      errmsg = "Invalid property value (#{property_value}: #{property_value.class.name}) for type (#{property_type})"
      case property_type
        when 'INT'
          raise errmsg unless property_value.is_a?(Integer)
        when 'FLOAT'
          raise errmsg unless (property_value.is_a?(Float) || property_value.is_a?(Integer))
        when 'BOOL'
          raise errmsg unless (property_value.is_a?(TrueClass) || property_value.is_a?(FalseClass))
        when 'DATE'
          raise errmsg unless property_value.is_a?(Date)
        when 'TIMESTAMP'
          raise errmsg unless property_value.is_a?(DateTime)
        when 'STRING'
          raise errmsg unless property_value.is_a?(String)
        else
          raise "Unknown property type: #{property_type}"
      end
    end

    # This class method handles conversion on the way out of the db:
    # mysql VARCHAR --> [ActiveRecord] --> ruby String --> [convert_string_value] --> ruby data type
    #
    def convert_string_value(property_value, property_type)
      return nil if property_value.nil?
      errmsg = "Invalid property value (#{property_value}) for type (#{property_type})"
      case property_type
        when 'INT'
          raise errmsg unless property_value =~ /^-?[0-9]+$/
          property_value.to_i
        when 'FLOAT'
          raise errmsg unless property_value =~ /^[+-]?[0-9]+\.?[0-9]*([Ee][+-]?[0-9]+)?$/
          property_value.to_f
        when 'BOOL'
          raise errmsg unless %w(0 1).include? property_value
          property_value == "1"
        when 'DATE'
          begin
            Date.parse(property_value)
          rescue => e
            raise (errmsg + ": " + e.message)
          end
        when 'TIMESTAMP'
          begin
            DateTime.parse(property_value)
          rescue => e
            raise (errmsg + ": " + e.message)
          end
        when 'STRING'
          property_value.to_s
        else
          raise "Unknown property type: #{property_type}"
      end
    end
  end # class << self
end
