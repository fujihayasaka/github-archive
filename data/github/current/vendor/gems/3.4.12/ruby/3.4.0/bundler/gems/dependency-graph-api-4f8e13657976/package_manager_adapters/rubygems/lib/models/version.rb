module Models
  class Version < Base
    belongs_to :rubygem

    has_one :linkset, through: :rubygem

    has_one :download_count

    has_many :dependencies

    has_many :gem_downloads

    def package_name
      rubygem.name
    end

    def package_version
      number
    end

    def downloads
      download_count&.count.to_i
    end

    def external_id
      id
    end

    def source_url
      linkset.try(:code)
    end

    def home_url
      linkset.try(:home)
    end

    def docs_url
      linkset.try(:docs)
    end
  end
end
