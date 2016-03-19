# == Schema Information
#
# Table name: property_definitions
#
#  property_id    :integer          not null, primary key
#  property_owner :string(10)       not null
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

PROPERTY_DEFINITION_DEFAULT_VALUES = [
  ->{ Faker::Number.between(1,100) },
  ->{ Faker::Number.decimal(2) },
  ->{ [true, false].sample },
  ->{ Faker::Hipster.word },
  ->{ Faker::Date.backward },
  ->{ Faker::Time.backward(Faker::Number.between(1,14)) },
] unless defined?(PROPERTY_DEFINITION_DEFAULT_VALUES)

FactoryGirl.define do
  factory :property_definition do
    property_owner { Faker::Internet.domain_word.upcase }

    property_name do
      o = property_owner[0].downcase
      w = default_value.nil? ? 'wod' : 'wd'
      t = property_type[0].downcase
      "#{o}_#{t}_#{w}_#{Faker::Number.between(0,9999)}"
    end
    description { Faker::Hipster.sentence(1)[0..99] }

    Hash[PropertyDefinition::PROPERTY_TYPES.zip(PROPERTY_DEFINITION_DEFAULT_VALUES)]
      .each do |property_type, default_value|
      trait "#{property_type.downcase}_without_default".to_sym do
        property_type property_type
        default_value nil
      end
      trait "#{property_type.downcase}_with_default".to_sym do
        property_type property_type
        default_value(&default_value)
      end
    end

  end
end
