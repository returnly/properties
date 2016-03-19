require "spec_helper"
require "properties"

class MyModelProperty < ActiveRecord::Base
  self.primary_keys = :my_model_id, :property_id, :seq_no
  belongs_to :my_model
  belongs_to :property_definition, foreign_key: :property_id
end

class MyModel < ActiveRecord::Base
  include Properties
end

FactoryGirl.define do
  factory :my_model do
  end
end

RSpec.describe Properties do

  [
    MyModel
  ].each do |model_class|

    model_sym = model_class.name.underscore.to_sym
    property_table_sym = model_class.property_class.table_name

    describe model_sym do

      before do
        PropertyDefinition.clear_caches
        @model0 = FactoryGirl.create(model_sym)

        # :with_properties trait creates an explicit property for each type (there are 6 types)
        # with default values and without default values, i.e. 6+6 = 12 properties; in addition
        # it creates an implicit property for each type with and without default; in addition
        # it creates a property sequence without default values, sequence length 2 for each type,
        # i.e. an additional 6 explicit properties, for a total of 18 explicit + 12 implicit.
        # In summary (wd = with default value, wod = without default value)
        #     6 explicit wd
        #     6 explicit wod
        #     6 seq explicit length 2 wod
        #     6 implicit wd
        #     6 implicit wod
        #  = 30 property definitions
        @model1 = FactoryGirl.create(model_sym, :with_properties)
      end

      describe 'DELETE ON CASCADE' do
        context "#{model_sym} instance gets deleted" do
          # 12 explicit non-seq properties + 6 seq properties of length 2 = 12+12
          it { expect { @model1.destroy }.to change { model_class.property_class.count }.by(-12-12) }
        end
        context 'property definition gets deleted' do
          it { expect {
            # non-seq property
            @model1.send(property_table_sym).first.property_definition.destroy
          }.to change { model_class.property_class.count }.by(-1) }
          it { expect {
            # seq property of length 2
            @model1.send(property_table_sym).last.property_definition.destroy
          }.to change { model_class.property_class.count }.by(-2) }
        end
      end

      describe '.implicit_properties' do
        subject { model_class.implicit_properties property_names }

        context 'empty input property names' do
          let(:property_names) { nil }
          before do
            expect(PropertyDefinition).to receive(:convert_string_value)
            .at_least(:once) { |property_value, _| property_value }
          end
          it { expect(subject.select { |k, v| k.to_s.include? "_wd_" }.size).to eq(6+6) }
          it { expect(subject.select { |k, v| k.to_s.include? "_wod_" }.size).to eq(6+6+6) }
          it 'only contains entries for this property owner' do
            subject.keys.select { |property_name| property_name =~ /^[po]_/ }.each do |property_name|
              expect(property_name.to_s).to start_with "#{model_sym[0]}_"
            end
          end
          it 'the property values match the corresponding property definition defaults' do
            subject.each do |property_name, property_value|
              expect(property_value).to eq(
                PropertyDefinition
                  .select(:default_value)
                  .where(property_owner: model_class.property_owner)
                  .find_by(property_name: property_name)
                  .default_value
              )
            end
          end
          context '2 property-owning model instances' do
            it { is_expected.to eq(@model0.implicit_properties property_names) }
            it { is_expected.to eq(@model1.implicit_properties property_names) }
          end
        end

        context '1 invalid input property names' do
          let(:property_names) { :bad_property_name }
          it { expect { subject }.to raise_error "Unknown properties: [:bad_property_name]" }
        end

        context '1 valid input property name' do
          let(:property_names) { a_property.property_name.to_sym }
          let(:a_property) { PropertyDefinition.where(property_owner: model_class.property_owner).first }
          before do
            expect(PropertyDefinition).to receive(:convert_string_value)
              .once { |property_value, _| property_value }
          end
          it { is_expected.to eq({
            a_property.property_name.to_sym => a_property.default_value
          }) }
        end

        context '2 valid input property names' do
          let(:property_names) { two_properties.map { |p| p.property_name.to_sym } }
          let(:two_properties) do
            [PropertyDefinition.where(property_owner: model_class.property_owner).first,
              PropertyDefinition.where(property_owner: model_class.property_owner).last]
          end
          before do
            expect(PropertyDefinition).to receive(:convert_string_value)
              .twice { |property_value, _| property_value }
          end
          it { is_expected.to eq({
            two_properties[0].property_name.to_sym => two_properties[0].default_value,
            two_properties[1].property_name.to_sym => two_properties[1].default_value
          }) }
        end
      end

      describe '#explicit_properties' do
        subject { @model1.explicit_properties property_names }

        context 'empty input property names' do
          let(:property_names) { nil }
          before do
            # 6 explicit wd + 6 explicit wod + 6 seq explicit length 2 => 24
            expect(PropertyDefinition).to receive(:convert_string_value)
              .exactly(6+6+6+6).times { |property_value, _| property_value }
          end
          it { expect(subject.size).to eq(6+6+6) }
          it 'only contains entries for this property owner (o)' do
            subject.keys.each do |property_name|
              expect(property_name.to_s).to start_with "#{model_sym[0]}_"
            end
          end
          it { expect(subject.select { |k, v| k.to_s.include? "_wd_" }.size).to eq(6) }
          it { expect(subject.select { |k, v| k.to_s.include? "_wod_" }.size).to eq(6+6) }
          it { expect(subject.values.flatten).to contain_exactly(
            *@model1.send(property_table_sym).order(:property_id, :seq_no).flatten.map(&:property_value)
          )}
        end

        context '1 invalid input property names' do
          let(:property_names) { :bad_property_name }
          it { expect { subject }.to raise_error "Unknown properties: [:bad_property_name]" }
        end

        context '1 valid input property name' do
          let(:property_names) { a_property.property_definition.property_name.to_sym }
          let(:a_property) { @model1.send(property_table_sym).first }
          before do
            expect(PropertyDefinition).to receive(:convert_string_value)
              .once { |property_value, _| property_value }
          end
          it { is_expected.to eq({
            a_property.property_definition.property_name.to_sym => a_property.property_value
          }) }
        end

        context '2 valid input property names' do
          let(:property_names) { two_properties.map { |p| p.property_definition.property_name.to_sym } }
          let(:two_properties) do
            [@model1.send(property_table_sym)[0],
              @model1.send(property_table_sym)[1]]
          end
          before do
            expect(PropertyDefinition).to receive(:convert_string_value)
              .exactly(2).times { |property_value, _| property_value }
          end
          it { is_expected.to eq({
            two_properties[0].property_definition.property_name.to_sym => two_properties[0].property_value,
            two_properties[1].property_definition.property_name.to_sym => two_properties[1].property_value
          }) }
        end

        context 'no explicit properties' do
          subject { @model0.explicit_properties property_names }
          context 'empty input property name' do
            let(:property_names) { nil }
            it { is_expected.to eq({}) }
          end
          context '1 invalid input property name' do
            let(:property_names) { :whatever }
            it { expect { subject }.to raise_error "Unknown properties: [:whatever]" }
          end
        end

        context 'inconsistent in-memory caches' do
          let(:property_definition) { @model1.send(property_table_sym).last.property_definition }
          let(:property_names) { property_definition.property_name.to_sym }
          before do
            expect(PropertyDefinition).to receive(:all_by_property_name_for)
              .once { {property_definition.property_name => {
              property_id: property_definition.id, property_type: 'INT'}}
            }
            expect(PropertyDefinition).to receive(:all_by_property_id_for)
              .once { {} } # e.g. cache was cleared by another thread
          end
          it { expect { subject }.to raise_error "in-memory property not found for property id #{property_definition.id}" }
        end
      end

      describe '.eq?' do
        subject { model_class.eq?(a, b) }
        context 'different class' do
          let(:a) { 4 }
          let(:b) { 4.0 }
          it { is_expected.to be false }
        end
        context 'two floats' do
          let(:a) { 4.1 }
          context 'abs difference greater than threshold' do
            let(:b) { 4.1 + (2*1e-14) }
            it { is_expected.to be false }
          end
          context 'abs difference within threshold' do
            let(:b) { 4.1 + (1e-14 / 2.0) }
            it { is_expected.to be true }
          end
        end
      end

      describe '#properties' do
        subject { @model1.properties property_names }

        context '1 invalid input property names' do
          let(:property_names) { :bad_property_name }
          it { expect { subject }.to raise_error "Unknown properties: [:bad_property_name]" }
        end

        context '1 valid input property name' do
          before do
            expect(@model1).to receive(:implicit_properties).once { {
              some_property_name: "somevalue",
              implicit_only_name: "i'm implicit"
            } }
            expect(@model1).to receive(:explicit_properties).once { {
              some_property_name: "someothervalue",
            } }
          end
          let(:property_names) { :some_property_name }
          it { is_expected.to eq({
            some_property_name: "someothervalue",
            implicit_only_name: "i'm implicit"
          }) }
        end
      end

      describe '.define_property_methods' do
        model_class.implicit_properties.keys.each do |property_name|
          context property_name do
            it { @model0.respond_to? property_name.to_s }
            it { expect(@model0.send(property_name)).to eq(@model0.properties(property_name)[property_name]) }
          end
        end
      end

      describe '.determine_action' do
        subject { model_class.determine_action explicit, implicit, property_name, property_value }
        let(:property_name) { :intensity }
        let(:property_value) { 10 }

        context 'input property name not an implicit property' do
          let(:explicit) { nil }
          let(:implicit) { {} }
          it { expect { subject }.to raise_error "Unknown property: intensity" }
        end

        context 'input property name matches an explicit property name' do
          context '...and input property value matches explicit property value' do
            context '...and input property value matches implicit default value' do
              let(:explicit) { {intensity: 10} }
              let(:implicit) { {intensity: 10} }
              it { is_expected.to eq(:delete) }
            end
            context '...and input property value does not match implicit property value' do
              let(:explicit) { {intensity: 10} }
              let(:implicit) { {intensity: nil} }
              it { is_expected.to eq(:none) }
            end
          end
          context '...and input property value does not match explicit property value' do
            context '...but it matches the implicit property default value' do
              let(:explicit) { {intensity: 11} }
              let(:implicit) { {intensity: 10} }
              it { is_expected.to eq(:delete) }
            end
            context '...and it does not match the implicit property value' do
              let(:explicit) { {intensity: 11} }
              let(:implicit) { {intensity: 9} }
              it { is_expected.to eq(:update) }
            end
          end
        end

        context 'input property name does not match an explicit property name' do
          context '...but it matches the implicit property default value' do
            let(:explicit) { {} }
            let(:implicit) { {intensity: 10} }
            it { is_expected.to eq(:none) }
          end
          context '...and it does not match the implicit property value' do
            let(:explicit) { {} }
            let(:implicit) { {intensity: nil} }
            it { is_expected.to eq(:insert) }
          end
        end
      end

      describe '#validate_and_pack' do
        subject { model.validate_and_pack property_name, property_value }
        let(:model) { FactoryGirl.build(model_sym, id: 345) }
        let(:property_name) { :intensity }
        let(:property_value) { 10 }

        context 'property name not found in all properties for this owner' do
          before do
            expect(PropertyDefinition).to receive(:all_by_property_name_for)
              .once.with(model_class.property_owner) { {} }
          end
          it { expect { subject }.to raise_error "Unknown property: intensity" }
        end

        context 'non-seq property' do
          context 'property name found in all properties for this owner' do
            context 'passed validation of value against type' do
              before do
                expect(PropertyDefinition).to receive(:all_by_property_name_for)
                  .once.with(model_class.property_owner) { {"intensity" => {property_id: 123, property_type: "INT"}} }
                expect(PropertyDefinition).to receive(:validate_value_against_type)
                  .once.with(property_value, "INT") { nil }
              end
              it { is_expected.to eq([{
                selector: {"#{model_sym}_id".to_sym => 345, property_id: 123, :seq_no => 0},
                setter: {property_value: 10}
              }]) }
            end
          end
        end

        context 'seq property' do
          let(:property_name) { :tag }
          let(:property_value) { %w(tag0 tag1) }
          context 'property name found in all properties for this owner' do
            context 'passed validation of value against type' do
              before do
                expect(PropertyDefinition).to receive(:all_by_property_name_for)
                  .once.with(model_class.property_owner) { {"tag" => {property_id: 123, property_type: "STRING"}} }
                expect(PropertyDefinition).to receive(:validate_value_against_type)
                  .once.with("tag0", "STRING") { nil }
                expect(PropertyDefinition).to receive(:validate_value_against_type)
                  .once.with("tag1", "STRING") { nil }
              end
              it { is_expected.to eq([
                {
                selector: {"#{model_sym}_id".to_sym => 345, property_id: 123, :seq_no => 0},
                setter: {property_value: "tag0"}
                },
                {
                  selector: {"#{model_sym}_id".to_sym => 345, property_id: 123, :seq_no => 1},
                  setter: {property_value: "tag1"}
                }
              ]) }
            end
          end

          context 'property definition has default value' do
            before do
              expect(PropertyDefinition).to receive(:all_by_property_name_for)
                .once.with(model_class.property_owner) { {"tag" => {property_id: 123, property_type: "STRING", default_value: "default"}} }
            end
            it { expect { subject }.to raise_error "Unsupported sequence property (tag) with non-nil default value (default)" }
          end
        end
      end

      describe '#properties=' do
        subject { @model.properties = properties_hash }
        before do
          @model = FactoryGirl.build(model_sym, id: 345)
        end

        context 'no actions to persist' do
          let(:properties_hash) { {a: 1, b: 2.0, c: [true, false]} }
          let(:actions) { {insert: [], update: [], delete: []} }
          before do
            expect(@model).to receive(:implicit_properties)
              .with(%i(a b c)).once { {a: nil, b: 2.0, c: nil} }
            expect(@model).to receive(:explicit_properties)
              .with(no_args).once { {a: 1, c: [true, false]} }
            expect(@model).to receive(:persist_actions)
              .with(actions).once
          end
          it { is_expected.to eq(properties_hash) }
        end

        context 'no actions to persist (integration test)', :without_transaction do
          let(:properties_hash) { @model.properties }
          before do
            @model = @model1
            expect(@model).to receive(:persist_actions).once.with(
              {insert: [], update: [], delete: []}
            )
          end
          it { is_expected.to eq(properties_hash) }
        end

        context '2 actions of each' do
          let(:properties_hash) { {a: 1, b: 2, c: 3, d: 4, e: [5.1, 5.2], f: 6} }
          let(:actions) { {insert: %i(a b), update: %i(c d), delete: %i(f g)} }
          before do
            expect(@model).to receive(:implicit_properties)
              .with(%i(a b c d e f)).once {
              {a: nil, b: 3, c: 1, d: nil, e: nil, f: 6}
            }
            expect(@model).to receive(:explicit_properties)
              .with(no_args).once {
              {c: 2, d: 3, e: [5.1, 5.2], f: 6, g: 7}
            }
            expect(@model).to receive(:get_property_id_from).twice { |property_name| property_name }
            expect(@model).to receive(:validate_and_pack).exactly(4).times { |property_name| [property_name] }
            expect(@model).to receive(:persist_actions)
              .with(actions).once
          end
          it { is_expected.to eq(properties_hash) }
        end
      end

      context 'integration test' do

        it 'retrieval and assignment are consistent', :without_transaction do

          FactoryGirl.create(:property_definition, property_name: 'x',
            property_owner: model_class.property_owner, property_type: 'INT', default_value: 7)
          expect(@model0.implicit_properties).to include(x: 7)
          expect(@model0.explicit_properties).not_to include(x: 7)
          expect(@model0.properties).to include(x: 7)

          @model0.properties = {x: 8}
          expect(@model0.implicit_properties).to include(x: 7)
          expect(@model0.explicit_properties).to include(x: 8)
          expect(@model0.properties).to include(x: 8)

          # now we change the default value of the implicit property to match the value
          # of the explicit one, thus making the explicit one redundant
          PropertyDefinition
            .find_by(property_name: 'x', property_owner: model_class.property_owner)
            .update!(default_value: 8) # <-- this clears mem caches in after_save

          expect(@model0.implicit_properties).to include(x: 8) # <-- it's up to date.
          expect(@model0.explicit_properties).to include(x: 8) # <-- this one has become redundant
          expect(@model0.properties).to include(x: 8)

          # now that the caches are up-to-date, if we perform another assignment
          # this time properties= will detect the redundancy of the explicit property
          # and get rid of it
          @model0.properties = {x: 8}
          expect(@model0.implicit_properties).to include(x: 8)
          expect(@model0.explicit_properties).not_to include(x: 8)
          expect(@model0.properties).to include(x: 8)
        end

      end
    end
  end
end
