require "minitest/autorun"
require "sinatra/base"
require "json"
require "models"

Models::Base.establish_connection({
  adapter: :postgresql,
  pool: 5,
  timeout: 5000,
  database: "rubygems"
})

def reset_database
  Models::Base.connection.tap do |c|
    c.execute("DROP MATERIALIZED VIEW IF EXISTS download_counts")

    c.drop_table :rubygems if c.table_exists?(:rubygems)

    c.create_table :rubygems do |t|
      t.string :name
    end

    c.drop_table :versions if c.table_exists?(:versions)

    c.create_table :versions do |t|
      t.references :rubygem
      t.string :authors
      t.string :number
      t.text :description
      t.timestamp :updated_at
      t.timestamp :yanked_at
      t.timestamp :built_at
    end

    c.drop_table :dependencies if c.table_exists?(:dependencies)

    c.create_table :dependencies do |t|
      t.references :rubygem
      t.references :version
      t.string :scope
      t.string :requirements
    end

    c.drop_table :linksets if c.table_exists?(:linksets)

    c.create_table :linksets do |t|
      t.references :rubygem
      t.string :code
    end

    c.drop_table :gem_downloads if c.table_exists?(:gem_downloads)

    c.create_table :gem_downloads do |t|
      t.references :version
      t.integer :count
    end
  end
end

class FakeSink < Sinatra::Base
  set :port, 7788

  def self.reset
    @package_releases = []
    @checkpoints = Hash.new { |h, k| h[k] = 0 }
  end

  def self.package_releases
    @package_releases
  end

  def self.checkpoints
    @checkpoints
  end

  post "/package_releases" do
    self.class.package_releases.concat(Array(JSON.parse(params[:package_releases])))

    "OK"
  end

  get "/checkpoints/:id" do
    { value: self.class.checkpoints[params[:id]] }.to_json
  end

  put "/checkpoints/:id" do
    self.class.checkpoints[params[:id]] = params[:value]
  end
end
