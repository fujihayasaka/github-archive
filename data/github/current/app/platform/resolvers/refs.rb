# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Refs < Resolvers::Base
      include Scientist

      type Connections::Ref, null: false
      argument :query, String, "Filters refs with query on name", required: false

      def resolve(**arguments)
        case @object
        when ::Repository
          async_can_list_refs?(object).then do |can_list_refs|
            if can_list_refs
              resolve_for_repo(**arguments)
            else
              ArrayWrapper.new
            end
          end
        when ::ProtectedBranch
          object.async_repository.then do |repo|
            async_can_list_refs?(repo).then do |can_list_refs|
              if can_list_refs
                resolve_for_branch_protection_rule(**arguments)
              else
                ArrayWrapper.new
              end
            end
          end
        end
      end

      protected

      def async_can_list_refs?(repository)
        context[:permission].async_owner_if_org(repository).then do |org|
          context[:permission].access_allowed?(:list_refs, resource: repository, current_repo: repository, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve_for_repo(**arguments)
        @object.async_network.then do
          unless arguments[:ref_prefix].start_with?("refs/")
            raise Errors::Validation, "`refPrefix` must start with `refs/`."
          end

          unless arguments[:ref_prefix].end_with?("/")
            raise Errors::Validation, "`refPrefix` must end with a `/`."
          end

          refs = if arguments[:ref_prefix].start_with?("refs/tags/") && arguments[:order_by] && arguments[:order_by][:field] == :tag_commit_date && arguments[:query].present?
            tags = @object.sorted_tags(pattern: arguments[:query])

            defaultOrder = tags.order
            user_direction = (arguments[:order_by] && arguments[:order_by][:direction] || arguments[:direction])
            direction = (user_direction || "ASC").downcase

            unless direction.to_sym == defaultOrder
              tags.reverse!
            end

            tags.to_a
          else
            if arguments[:ref_prefix].start_with?("refs/tags/") && arguments[:order_by] && arguments[:order_by][:field] == :tag_commit_date
              tags = @object.sorted_tags
            else
              tags = @object.refs
            end

            defaultOrder = tags.order
            user_direction = (arguments[:order_by] && arguments[:order_by][:direction] || arguments[:direction])
            direction = (user_direction || "ASC").downcase

            unless direction.to_sym == defaultOrder
              tags.reverse!
            end

            if arguments[:query]
              ArrayWrapper.new(tags.filter(arguments[:ref_prefix]).substring_filter(substring: arguments[:query].downcase, limit: tags.count, case_sensitive: false).to_a)
            else
              ArrayWrapper.new(tags.filter(arguments[:ref_prefix]).to_a)
            end
          end

          ArrayWrapper.new(refs)
        end
      end

      def resolve_for_branch_protection_rule(**arguments)
        @object.async_repository.then do |repository|
          Platform::Loaders::BranchProtectionRule::MatchesAndConflicts.load(repository, @object).then do |information|
            if arguments[:query].present?
              substring = arguments[:query].b.downcase
              information[:matches] = information[:matches].filter { |ref| ref.name.downcase.include?(substring) }
            end
            ArrayWrapper.new(information[:matches])
          end
        end
      end
    end
  end
end
