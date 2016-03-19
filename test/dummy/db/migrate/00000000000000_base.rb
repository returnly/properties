class Base < ActiveRecord::Migration
  def up
    return if Rails.env.production?

    format = ActiveRecord::Base.schema_format
    db_dir = Rails.application.config.paths["db"].first
    file = File.join(db_dir, "base.sql")
    ActiveRecord::Tasks::DatabaseTasks.load_schema_current(format, file)
  end
end
