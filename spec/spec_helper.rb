# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require File.expand_path("../../test/dummy/config/environment.rb",  __FILE__)

require "rspec/rails"
require "factory_girl"
require "faker"
require "composite_primary_keys"
require "factories/properties"
require "database_cleaner"

ActiveRecord::Migrator.migrations_paths = [File.expand_path("../../test/dummy/db/migrate", __FILE__)]

# Checks for pending migration and applies them before tests are run
ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|

  config.use_transactional_fixtures = false

  config.before :each do
    if RSpec.current_example.metadata[:without_transaction]
      DatabaseCleaner.strategy = :truncation
    else
      DatabaseCleaner.strategy = :transaction
    end
    DatabaseCleaner.start
  end

  config.after :each do
    DatabaseCleaner.clean
  end

end
