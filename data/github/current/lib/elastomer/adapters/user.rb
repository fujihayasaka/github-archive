# typed: false
# frozen_string_literal: true

module Elastomer::Adapters

  # The User adapter is used to transform a user ActiveRecord object into a
  # Hash document that can be indexed in ElasticSearch.
  class User < ::Elastomer::Adapter

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "Users"
    end

    def self.mysql_cluster
      ::User.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    def model
      @model ||= ::User.find_by_id(document_id)
    end
    alias :user :model

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    def to_hash
      if model.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash
      @hash = nil

      return unless user.searchable?

      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        login: user.login,
        email: user.profile_email,
        all_emails: all_emails,
        user_id: user.id,
        followers: user.followers_count(viewer: nil),
        repos: user.public_repositories.count,
        name: user.profile_name,
        location: user.profile_location,
        organization: user.is_a?(::Organization),
        created_at: user.created_at,
        updated_at: user.updated_at,
        profile_bio: user.profile_bio,
        suspended_at: user.suspended_at,
        sponsorable: user.sponsorable?,
      }

      unless user.is_a?(::Organization)
        @hash[:all_org_ids] = user.organization_ids
        @hash[:public_org_ids] = user.public_organizations.pluck(:id)
      end

      if user.is_a?(::Organization) && user.enterprise_managed_user_enabled?
        @hash[:business_id] = user.business&.id
      elsif user.is_enterprise_managed?
        @hash[:business_id] = user.business_user_accounts&.first&.business_id
      end

      if language = user.primary_language
        @hash[:language]    = language.linguist_name
        @hash[:language_id] = language.linguist_id
      end

      # Important to note that Organizations take a hit on rank because they don't have
      # followers by design.
      rank  = 1.0
      rank +=     Math.log10(@hash[:repos])     if @hash[:repos] > 0
      rank += 2 * Math.log10(@hash[:followers]) if @hash[:followers] > 0
      @hash[:rank] = rank

      @hash
    end

    # Internal: Generate an array of all the email address associted with the
    # User model. This includes gravatar email, billing email, profile email,
    # and all the other registered email address.
    #
    # Returns an Array of email address Strings.
    def all_emails
      ary = user.emails.map(&:email)
      ary << user.profile_email
      ary << user.gravatar_email
      ary << user.organization_billing_email
      ary.compact!
      ary.uniq!
      ary
    end
  end  # User
end  # Elastomer::Adapters
