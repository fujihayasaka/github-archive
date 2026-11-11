# typed: false
# frozen_string_literal: true

module Platform
  module Loaders
    class RedirectedRepositoryByOldOwner < Platform::Loader
      def self.load(network_id, old_owner_name)
        self.for(network_id).load(old_owner_name)
      end

      def self.load_all(network_id, old_owner_names)
        loader = self.for(network_id)
        Promise.all(old_owner_names.map { |old_owner_name| loader.load(old_owner_name) })
      end

      def initialize(network_id)
        @network_id = network_id
      end

      def fetch(old_owner_names)
        ::RepositoryRedirect
          .joins(:repository)
          .includes(:repository)
          .where("repositories.source_id = ?", @network_id)
          .where(
            (["repository_name LIKE ?"] * old_owner_names.length).join(" OR "),
            *old_owner_names.map { |name| "#{::ActiveRecord::Base.sanitize_sql_like(name)}/%" })
          .order("repository_redirects.created_at DESC, repository_redirects.id DESC")
          .group_by(&:repository_name)
          .map { |name, rrs| [name.split("/").first, rrs.first.repository] }
          .to_h
      end
    end
  end
end
