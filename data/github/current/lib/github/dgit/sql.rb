# typed: true
# frozen_string_literal: true

require "application_record/domain/spokes"
require "github/throttler"

module GitHub
  class DGit
    class SpokesSQL < ::GitHub::SQL # rubocop:disable GitHub/DoNotAllowSubclassingOfGitHubSQL
      def connection
        ApplicationRecord::Domain::Spokes.connection
      end
    end

    # Wrapper around ::GitHub::SQL which raises an ArgumentError
    # if ever it is used without a bound :gist_id.
    class GistSpokesSQL < SpokesSQL
      attr_reader :gist_id_added

      def add(sql, extras = nil)
        @gist_id_added ||= (extras && extras.key?(:gist_id))
        super
      end

      def results
        raise ArgumentError, "missing :gist_id in @binds" if !@gist_id_added && (@binds.nil? || !@binds.key?(:gist_id))
        super
      end
    end

    # Wrapper around ::GitHub::SQL which raises an ArgumentError
    # if ever it is used without a bound :network_id.
    class NetworkSpokesSQL < SpokesSQL
      attr_reader :network_id_added

      def add(sql, extras = nil)
        @network_id_added ||= (extras && extras.key?(:network_id))
        super
      end

      def results
        raise ArgumentError, "missing :network_id in @binds" if !@network_id_added && (@binds.nil? || !@binds.key?(:network_id))
        super
      end
    end

    class ReposSpokesSQL < SpokesSQL
      attr_reader :repo_ids_added

      def add(sql, extras = nil)
        @repo_ids_added ||= (extras && extras.key?(:repo_ids))
        super
      end

      def results
        raise ArgumentError, "missing :repo_ids in @binds" if !@repo_id_added && (@binds.nil? || !@binds.key?(:repo_ids))
        super
      end
    end

    class DB
      SPOKES = 1

      DUAL_TYPE = {
        SPOKES => "spokes",
      }

      def self.dual_types
        if GitHub::AppEnvironment.production? && !GitHub.enterprise?
          DUAL_TYPE.keys
        else
          [SPOKES]
        end
      end

      def self.fileserver_types
        dual_types
      end

      def self.gist_types
        dual_types
      end

      def self.network_types
        dual_types
      end

      def self.gist_db_type_for_gist_id(gist_id)
        SPOKES
      end

      def self.gist_db_name_for_gist_id(gist_id)
        ::GitHub::DGit::DB::DUAL_TYPE[gist_db_type_for_gist_id(gist_id)]
      end

      def self.for_gist_id(gist_id)
        case gist_db_type_for_gist_id(gist_id)
        when SPOKES
          GistIDSpokesHelper.new(gist_id: gist_id)
        end
      end

      def self.each_for_gist_ids(gist_ids)
        return if gist_ids.empty?
        yield for_gist_maintenance(SPOKES), gist_ids
      end

      def self.network_db_type_for_network_id(network_id)
        SPOKES
      end

      def self.network_db_name_for_network_id(network_id)
        ::GitHub::DGit::DB::DUAL_TYPE[network_db_type_for_network_id(network_id)]
      end

      def self.for_network_id(network_id)
        case network_db_type_for_network_id(network_id)
        when SPOKES
          NetworkIDSpokesHelper.new(network_id: network_id)
        end
      end

      def self.for_repo_ids(repo_ids)
        RepoIDsSpokesHelper.new(repo_ids: repo_ids)
      end

      def self.each_for_network_ids(network_ids)
        return if network_ids.empty?
        yield for_network_maintenance(SPOKES), network_ids
      end

      def self.for_gist_maintenance(db_type)
        for_dual_maintenance(db_type)
      end

      def self.for_network_maintenance(db_type)
        for_dual_maintenance(db_type)
      end

      def self.for_fileserver_maintenance(db_type)
        for_dual_maintenance(db_type)
      end

      def self.for_dual_maintenance(db_type)
        case db_type
        when SPOKES
          SpokesDBHelper.new
        else
          raise ArgumentError, "invalid db_type: #{db_type}"
        end
      end

      def self.each_fileserver_db
        return enum_for(:each_fileserver_db) unless block_given?
        ::GitHub::DGit::DB.fileserver_types.each do |t|
          db = GitHub::DGit::DB.for_fileserver_maintenance(t)
          yield db
        end
      end

      def self.each_gist_db
        return enum_for(:each_gist_db) unless block_given?
        ::GitHub::DGit::DB.gist_types.each do |t|
          db = GitHub::DGit::DB.for_gist_maintenance(t)
          yield db
        end
      end

      def self.each_network_db
        return enum_for(:each_network_db) unless block_given?
        ::GitHub::DGit::DB.network_types.each do |t|
          db = GitHub::DGit::DB.for_network_maintenance(t)
          yield db
        end
      end

      class FS
        class SQL < ::GitHub::DGit::SpokesSQL
        end # FS::SQL
      end # FS

      class DC
        class SQL < ::GitHub::DGit::SpokesSQL
        end # DC::SQL
      end # DC
    end

    class SpokesDBHelper
      attr_reader :db_type
      attr_reader :name
      attr_reader :SQL

      def initialize
        @db_type = ::GitHub::DGit::DB::SPOKES
        @name = ::GitHub::DGit::DB::DUAL_TYPE[@db_type]
        @SQL = ::GitHub::DGit::SpokesSQL
      end

      def transaction
        ApplicationRecord::Domain::Spokes::transaction { yield }
      end

      def connection
        ApplicationRecord::Domain::Spokes.connection
      end

      def throttle
        ApplicationRecord::Domain::Spokes.throttle { yield }
      end
    end

    class GistIDSpokesHelper < ::GitHub::DGit::SpokesDBHelper
      attr_reader :gist_id
      attr_reader :SQL

      def initialize(gist_id:)
        super()
        @gist_id = gist_id
        @SQL = ::GitHub::DGit::GistSpokesSQL
      end
    end

    class NetworkIDSpokesHelper < ::GitHub::DGit::SpokesDBHelper
      attr_reader :network_id
      attr_reader :SQL

      def initialize(network_id:)
        super()
        @network_id = network_id
        @SQL = ::GitHub::DGit::NetworkSpokesSQL
      end
    end

    class RepoIDsSpokesHelper < ::GitHub::DGit::SpokesDBHelper
      attr_reader :repo_ids
      attr_reader :SQL

      def initialize(repo_ids:)
        super()
        @repo_ids = repo_ids
        @SQL = ::GitHub::DGit::ReposSpokesSQL
      end
    end
  end
end
