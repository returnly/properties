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

require 'spec_helper'

RSpec.describe PropertyDefinition do

  describe '#new' do
    subject { FactoryGirl.build(:property_definition, default_value: value, property_type: type) }
    context 'invalid type' do
      let(:type) { "UNICORN" }
      let(:value) { "whatever" }
      it { is_expected.to be_invalid }
      it { subject.valid?; expect(subject.errors[:property_type]).to include "Unknown property type: UNICORN" }
    end
    context 'nil value' do
      PropertyDefinition::PROPERTY_TYPES.each do |_type|
        let(:type) { _type }
        let(:value) { nil }
        it { is_expected.to be_valid }
      end
    end
    context 'inconsistent default value <-> property type' do
      let(:type) { 'INT' }
      let(:value) { "1.4" }
      it { is_expected.to be_invalid }
      it { subject.valid?; expect(subject.errors[:default_value]).to include "Invalid property value (1.4) for type (INT)" }
    end
  end

  describe '#convert_string_value' do
    subject { described_class.convert_string_value(property_value, property_type) }
    context 'invalid property type' do
      let(:property_value) { "whatever" }
      let(:property_type) { "UNICORN" }
      it { expect { subject }.to raise_error "Unknown property type: UNICORN" }
    end
    context 'nil property value' do
      let(:property_value) { nil }
      let(:property_type) { "WHATEVER" }
      it { is_expected.to be_nil }
    end
    context 'valid INT' do
      let(:property_value) { "-12" }
      let(:property_type) { "INT" }
      it { is_expected.to eq(-12) }
    end
    context 'invalid INT' do
      let(:property_value) { "-1.2" }
      let(:property_type) { "INT" }
      it { expect { subject }.to raise_error "Invalid property value (-1.2) for type (INT)" }
    end
    context 'valid FLOAT' do
      let(:property_value) { "-1.2" }
      let(:property_type) { "FLOAT" }
      it { is_expected.to be_within(1e-10).of(-1.2) }
    end
    context 'valid FLOAT (scientific notation)' do
      let(:property_value) { "-0.25E+10" }
      let(:property_type) { "FLOAT" }
      it { is_expected.to be_within(1e-10).of(-0.25E+10) }
    end
    context 'invalid FLOAT' do
      let(:property_value) { "-1.2a" }
      let(:property_type) { "FLOAT" }
      it { expect { subject }.to raise_error "Invalid property value (-1.2a) for type (FLOAT)" }
    end
    context 'valid BOOL' do
      let(:property_value) { "1" }
      let(:property_type) { "BOOL" }
      it { is_expected.to be true }
    end
    context 'invalid BOOL' do
      let(:property_value) { "true" }
      let(:property_type) { "BOOL" }
      it { expect { subject }.to raise_error "Invalid property value (true) for type (BOOL)" }
    end
    context 'valid STRING' do
      let(:property_value) { "12" }
      let(:property_type) { "STRING" }
      it { is_expected.to eq("12") }
    end
    context 'valid DATE' do
      let(:property_value) { "2001-02-03" }
      let(:property_type) { "DATE" }
      it { is_expected.to eq(Date.new(2001,2,3)) }
    end
    context 'invalid DATE' do
      let(:property_value) { "abc" }
      let(:property_type) { "DATE" }
      it { expect { subject }.to raise_error /Invalid property value \(abc\) for type \(DATE\)/ }
    end
    context 'valid TIMESTAMP' do
      let(:property_value) { "2001-02-03T04:05:06+07:00" }
      let(:property_type) { "TIMESTAMP" }
      it { is_expected.to eq(DateTime.new(2001,2,3,4,5,6,'+7')) }
    end
    context 'invalid TIMESTAMP' do
      let(:property_value) { "abc" }
      let(:property_type) { "TIMESTAMP" }
      it { expect { subject }.to raise_error /Invalid property value \(abc\) for type \(TIMESTAMP\)/ }
    end
  end

  describe '#validate_value_against_type' do
    subject { described_class.validate_value_against_type(property_value, property_type) }
    context 'invalid property type' do
      let(:property_value) { "whatever" }
      let(:property_type) { "UNICORN" }
      it { expect { subject }.to raise_error "Unknown property type: UNICORN" }
    end
    context 'nil property value' do
      let(:property_value) { nil }
      let(:property_type) { "WHATEVER" }
      it { is_expected.to be_nil }
    end
    context 'valid INT' do
      let(:property_value) { -12 }
      let(:property_type) { "INT" }
      it { is_expected.to be_nil }
    end
    context 'invalid INT' do
      let(:property_value) { -1.2 }
      let(:property_type) { "INT" }
      it { expect { subject }.to raise_error "Invalid property value (-1.2: Float) for type (INT)" }
    end
    context 'valid FLOAT' do
      let(:property_value) { -1.2 }
      let(:property_type) { "FLOAT" }
      it { is_expected.to be_nil }
    end
    context 'valid FLOAT (scientific notation)' do
      let(:property_value) { -1.2e+4 }
      let(:property_type) { "FLOAT" }
      it { is_expected.to be_nil }
    end
    context 'valid FLOAT (integer)' do
      let(:property_value) { -4 }
      let(:property_type) { "FLOAT" }
      it { is_expected.to be_nil }
    end
    context 'invalid FLOAT' do
      let(:property_value) { "-1.2" }
      let(:property_type) { "FLOAT" }
      it { expect { subject }.to raise_error "Invalid property value (-1.2: String) for type (FLOAT)" }
    end
    context 'valid BOOL' do
      let(:property_value) { true }
      let(:property_type) { "BOOL" }
      it { is_expected.to be_nil }
    end
    context 'invalid BOOL' do
      let(:property_value) { 1 }
      let(:property_type) { "BOOL" }
      it { expect { subject }.to raise_error "Invalid property value (1: Fixnum) for type (BOOL)" }
    end
    context 'valid STRING' do
      let(:property_value) { "12" }
      let(:property_type) { "STRING" }
      it { is_expected.to be_nil }
    end
    context 'invalid STRING' do
      let(:property_value) { 12 }
      let(:property_type) { "STRING" }
      it { expect { subject }.to raise_error "Invalid property value (12: Fixnum) for type (STRING)" }
    end
    context 'valid DATE' do
      let(:property_value) { Date.new(2001,2,3) }
      let(:property_type) { "DATE" }
      it { is_expected.to be_nil }
    end
    context 'valid DATE (DateTime)' do
      let(:property_value) { DateTime.new(2001,2,3,4,5,6,'+7') }
      let(:property_type) { "DATE" }
      it { is_expected.to be_nil }
    end
    context 'invalid DATE' do
      let(:property_value) { "2014-02-02" }
      let(:property_type) { "DATE" }
      it { expect { subject }.to raise_error "Invalid property value (2014-02-02: String) for type (DATE)" }
    end
    context 'valid TIMESTAMP' do
      let(:property_value) { DateTime.new(2001,2,3,4,5,6,'+7') }
      let(:property_type) { "TIMESTAMP" }
      it { is_expected.to be_nil }
    end
    context 'invalid TIMESTAMP (Date)' do
      let(:property_value) { Date.new(2001,2,3) }
      let(:property_type) { "TIMESTAMP" }
      it { expect { subject }.to raise_error "Invalid property value (2001-02-03: Date) for type (TIMESTAMP)" }
    end
  end
end
