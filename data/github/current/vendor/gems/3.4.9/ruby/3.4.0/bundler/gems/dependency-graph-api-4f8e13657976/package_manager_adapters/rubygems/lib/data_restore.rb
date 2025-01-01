require "open3"

class DataRestore
  include Logging

  def self.load(**args)
    new(**args).load
  end

  def initialize(dump:, database:, user: nil, host: nil, password: nil)
    @dump = dump
    @database = database
    @host = host
    @user = user || `whoami`.strip
    @password = password
  end

  def load
    db_drop
    db_create

    logger.info("Loading data from #{dump}")

    unless File.exist?(dump)
      raise "Couldn't find dump file #{dump}"
    end

    cmd = <<-CMD
      #{set_pg_pass_if_present} tar xOf #{dump} public_postgresql/databases/PostgreSQL.sql.gz | \
      gunzip -c | \
      psql \
        #{set_pg_host_if_present} \
        -U #{user} \
        -d #{database}
    CMD

    _, errors, status = execute cmd

    unless status.success?
      raise "Failed to load data dump from #{dump}\n#{errors}"
    end
  end

  def db_drop
    logger.info("Dropping database #{database}")

    _, _, status = execute <<-CMD
      #{set_pg_pass_if_present} dropdb \
        #{set_pg_host_if_present} \
        -U #{user} \
        #{database} > \
        /dev/null 2>&1
    CMD

    unless status.success?
      logger.info("Database #{database} doesn't exist. Ignoring.")
    end
  end

  def db_create
    logger.info("Creating database #{database}")

    _, errors, status = execute <<-CMD
      #{set_pg_pass_if_present} createdb \
        #{set_pg_host_if_present} \
        -U #{user} \
        #{database} > \
        /dev/null
    CMD

    unless status.success?
      puts errors
      raise "Failed to create database #{database}\n#{errors}"
    end

    _, errors, status = execute <<-CMD
       #{set_pg_pass_if_present} psql -q \
        #{set_pg_host_if_present} \
        -U #{user} \
        -d #{database} \
        -c 'CREATE EXTENSION IF NOT EXISTS hstore';
    CMD

    unless status.success?
      raise "Failed to add hstore extension\n#{errors}"
    end
  end

  private

  def set_pg_host_if_present
    if @host.nil?
      ""
    else
      "-h #{@host}"
    end
  end

  def set_pg_pass_if_present
    if @password.nil?
      ""
    else
      "PGPASSWORD=#{@password}"
    end
  end

  attr_reader :dump, :database, :user

  def execute(command)
    Open3.capture3(command)
  end
end
