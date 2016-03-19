
PROPERTY_TYPE_TO_VALUE = Hash[PropertyDefinition::PROPERTY_TYPES.zip [
  ->{ Faker::Number.between(1,100).to_s },
  ->{ Faker::Number.decimal(2).to_s },
  ->{ %w(1 0).sample },
  ->{ Faker::Hipster.word },
  ->{ Faker::Date.backward.to_s },
  ->{ Faker::Time.backward(Faker::Number.between(1,14)).to_s },
]] unless defined?(PROPERTY_TYPE_TO_VALUE)

FactoryGirl.define do

  trait :with_properties do

    transient do
      seq_size { 2 }
    end

    after(:create) do |instance, evaluator|

      model_class = instance.class                         # e.g. OrderLine
      model_sym = model_class.name.underscore.to_sym       # e.g. :order_line
      property_owner = model_class.name.underscore.upcase  # e.g. ORDER_LINE
      property_sym = "#{model_sym}_property".to_sym        # e.g. :order_line_property

      begin
        FactoryGirl.factory_by_name(property_sym)
        # avoid re-registering factories
      rescue ArgumentError
        FactoryGirl.define do

          factory property_sym do
            send(model_sym)
            association :property_definition, :int_with_default, property_owner: property_owner
            seq_no 0
            property_value do
              # property value must not match the
              # property definition's default value
              property_type = property_definition[:property_type]
              default_value = property_definition[:default_value]
              value = nil
              begin
                value = PROPERTY_TYPE_TO_VALUE[property_type].call
              end until value != default_value
              value
            end

            PropertyDefinition::PROPERTY_TYPES.each do |property_type|
              %w(with without).each do |w|
                traitsym = "#{property_type.downcase}_#{w}_default".to_sym
                trait traitsym do
                  association :property_definition, traitsym, property_owner: property_owner
                end
              end
            end

          end
        end
      end # begin

      PropertyDefinition::PROPERTY_TYPES.each do |property_type|

        # create an instance for each property type
        #   with and without default values
        #     with and without a matching <model>_property
        #
        %w(with without).each do |w|
          traitsym = "#{property_type.downcase}_#{w}_default".to_sym
          create(property_sym, traitsym, model_sym => instance)
          create(:property_definition, traitsym, property_owner: property_owner)
        end

        # in addition, create a property sequence for each property type

        traitsym = "#{property_type.downcase}_without_default".to_sym
        property_definition = create(:property_definition, traitsym, property_owner: property_owner)
        (0...evaluator.seq_size).each do |seq_no|
          create(property_sym, traitsym, model_sym => instance, property_definition: property_definition, seq_no: seq_no)
        end
      end

    end # after(:create)
  end # :with_properties

end


