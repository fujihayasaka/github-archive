# typed: false
# frozen_string_literal: true

module Profiles
  module Achievements
    module ControllerMethods

      # Public: Given a set of Achievement unlocking models, return the subset of them that should be shown to the
      # current user. This accounts for both authzd checks, which verify readability permissions, and CAP filters,
      # like SSO requirements in owning organizations or IP filters. This implementation takes pains to avoid N+1
      # queries.
      #
      # unlocking_models - Enumerable collection of ActiveRecord models. Nested Arrays, such as RepositoryLists,
      #   will be flattened before processing.
      #
      # Returns a Set containing unlocking_models that pass all checks and are ok to display information about.
      def visible_unlocking_models(unlocking_models)
        authorized_unlocking_models(readable_unlocking_models(unlocking_models))
      end

      # Describe the "parent" ActiveRecord relationships that should be prefilled in batch and verified for presence
      # before checking readability via authzd. This prevents N+1 queries when generating authzd query attributes and
      # avoids problems in some models (like DiscussionPost) that raise with nil parent relations. The default,
      # `[]`, skips the prefill step.
      #
      # These relationships are described in a format compatible with that accepted by GitHub::PrefillAssociations,
      # or ActiveRecord's #include method:
      #
      # https://api.rubyonrails.org/classes/ActiveRecord/QueryMethods.html#method-i-includes
      PARENT_OBJECT_RELATIONS = {
        "CommitComment" => [:repository],
        "Commit" => [:repository],
        "DiscussionComment" => [:discussion, :repository],
        "Discussion" => [:repository],
        "DiscussionPost" => [{ team: :organization }],
        "DiscussionPostReply" => [{ discussion_post: { team: :organization } }],
        "IssueComment" => [:issue, :repository],
        "Issue" => [:repository],
        "PullRequest" => [:repository],
        "PullRequestReviewComment" => [:pull_request, :repository],
        "PullRequestReview" => [:pull_request, :repository],
        "Release" => [:repository],
        "RepositoryAdvisoryComment" => [{ repository_advisory: :repository }],
        "RepositoryAdvisory" => [:repository],
        "Repository" => [],
        "Sponsorship" => [],
      }

      # Internal: Given a set of Achievement unlocking models, return the subset of them that should be visible to
      # the current viewing user according to authzd and other logical permission mechanisms. Parent relations of each
      # model are prefilled and authzd queries are performed in a single batch for efficiency.
      #
      # unlocking_models - Enumerable collection of ActiveRecord models to verify. Embedded Arrays, like RepositoryList
      #   models, will be flattened prior to verification.
      #
      # Returns a Set containing elements of the flattened `unlocking_models` that are ok for the viewing user to see.
      def readable_unlocking_models(unlocking_models)
        flat_models = flatten_unlocking_models(unlocking_models)
        unlocking_models_by_strategy = flat_models.group_by do |model|
          PARENT_OBJECT_RELATIONS.fetch(model.class.name, [])
        end

        authz_promises = []
        model_readability = Hash.new(false)

        unlocking_models_by_strategy.each do |(parent_relations, unlocking_models)|
          if parent_relations.any?
            GitHub::PrefillAssociations.prefill_associations(unlocking_models, parent_relations) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          end

          # Traverse the parent relations we just preloaded and fail quickly if any are nil
          unlocking_models.each do |unlocking_model|
            promise = if any_nil_parents?(unlocking_model, parent_relations)
              Promise.resolve(false)
            elsif unlocking_model.respond_to?(:async_sponsor_readable_by?)
              # Sponsorships have separate _readable_by? methods for sponsor and amount. Special case them.
              unlocking_model.async_sponsor_readable_by?(current_user)
            elsif unlocking_model.respond_to?(:async_readable_by?)
              unlocking_model.async_readable_by?(current_user)
            elsif unlocking_model.respond_to?(:readable_by?)
              Promise.resolve(unlocking_model.readable_by?(current_user))
            else
              Promise.resolve(false)
            end

            authz_promises << promise.then { |visible| model_readability[unlocking_model] = visible }
          end
        end

        Promise.all(authz_promises).sync

        flat_models.select { |unlocking_model| model_readability[unlocking_model] }.to_set
      end

      # Describe the strategies used by #authorized_unlocking_models to traverse from an Achievement unlocking model
      # to the appropriate model that may be used by the CAP filter to make an authorization decision.
      #
      # Types not listed here will default to :identity and be passed directly to the CAP filter.
      AUTHORIZING_MODEL_STRATEGIES = {
        "CommitComment" => :repository,
        "DiscussionComment" => :repository,
        "IssueComment" => :repository,
        "PullRequestReviewComment" => :repository,
        "PullRequestReview" => :repository,
        "Release" => :repository,
        "RepositoryAdvisory" => :repository,
        "RepositoryAdvisoryComment" => :repository_by_advisory,
        "DiscussionPost" => :team,
        "DiscussionPostReply" => :team_by_post,
        "Sponsorship" => :sponsor,
      }.freeze

      # Internal: Given a set of Achievement unlocking event models, return a Set containing the subset of them that
      # pass the CAP filters for this request.
      #
      # This is complicated by the situation that not all -- indeed, most -- model types acceptable as unlocking
      # models cannot be directly passed to a CAP filter. Some, like DiscussionPost, belong to services in the
      # process of deprecating (:fingers_crossed:) and may _never_ be CAP-capable. So, we work around this by
      # prefilling then traversing model relations to arrive at an appropriate "owning" authorization model, like a
      # Repository or a Team, authorizing those, and filtering the original unlocking_models based on the decisions
      # made for their corresponding authorizing models.
      #
      # unlocking_models - Array of models associated with Achievement tiers we're about to display. Embedded Arrays,
      #   such as those from RepositoryLists, will be flattened.
      #
      # Returns a Set of the subset of provided flattened `unlocking_models` that are CAP-accessible.
      def authorized_unlocking_models(unlocking_models)
        unlocking_models_by_authorizing = Hash.new { |h, k| h[k] = [] }

        # The flatten_unlocking_models call in here handles RepositoryList unlocking models by inlining them and then
        # authorizing them directly with the :identity strategy.
        flat_models = flatten_unlocking_models(unlocking_models)
        unlocking_models_by_strategy = flat_models.flatten.group_by do |model|
          AUTHORIZING_MODEL_STRATEGIES.fetch(model.class.name, :identity)
        end
        unlocking_models_by_strategy.each do |(authorizing_model_strategy, unlocking_models)|
          case authorizing_model_strategy
          when :repository
            GitHub::PrefillAssociations.prefill_associations(
              unlocking_models,
              { repository: :owner },
            )
            unlocking_models.each do |unlocking_model|
              repo = unlocking_model.repository
              next unless repo
              next if user_or_org_opted_out?(repo.owner)

              unlocking_models_by_authorizing[repo] << unlocking_model
            end
          when :repository_by_advisory
            GitHub::PrefillAssociations.prefill_associations(
              unlocking_models,
              { repository_advisory: { repository: :owner } },
            )
            unlocking_models.each do |unlocking_model|
              repo = unlocking_model.repository_advisory&.repository
              next unless repo
              next if user_or_org_opted_out?(repo.owner)

              unlocking_models_by_authorizing[repo] << unlocking_model
            end
          when :team
            GitHub::PrefillAssociations.prefill_associations(
              unlocking_models,
              { team: :organization },
            )
            unlocking_models.each do |unlocking_model|
              team = unlocking_model.team
              next unless team
              next if user_or_org_opted_out?(team.organization)

              unlocking_models_by_authorizing[team] << unlocking_model
            end
          when :team_by_post
            GitHub::PrefillAssociations.prefill_associations(
              unlocking_models,
              { discussion_post: { team: :organization } },
            )
            unlocking_models.each do |unlocking_model|
              team = unlocking_model.discussion_post&.team
              next unless team
              next if user_or_org_opted_out?(team.organization)

              unlocking_models_by_authorizing[team] << unlocking_model
            end
          when :sponsor
            GitHub::PrefillAssociations.prefill_associations(unlocking_models, :sponsor)

            unlocking_models.each do |unlocking_model|
              next unless unlocking_model.sponsor

              unlocking_models_by_authorizing[unlocking_model.sponsor] << unlocking_model
            end
          else
            # :identity
            unlocking_models.each do |unlocking_model|
              unlocking_models_by_authorizing[unlocking_model] << unlocking_model
            end
          end
        end

        authorizing_model_candidates = unlocking_models_by_authorizing.keys.compact

        # Pre-filter authorizing_models to remove any models that will cause exceptions in the #authorized_resources
        # call. This means any .multiple_target_for_conditional_access() methods that return `nil` or omit results,
        # like pull requests in repositories that are being deleted or repositories with missing owners.
        #
        # Unfortunately, while cap_filter#safe_multiple_targets_for_conditional_access() does cache its results
        # internally, we can't use it directly to do this because it raises exceptions, which would leave the
        # remainder of its resources uncached (to potentially blow up below) even if we caught them.
        #
        # This should be okay because ActiveRecord will cache at least some of the relations prefilled by the
        # .multiple_target_for_conditional_access() calls here and prevent some redundant database traffic.
        authorizing_models = authorizing_model_candidates.group_by(&:class).flat_map do |(authorizing_class, models)|
          targets = authorizing_class.multiple_target_for_conditional_access(models)
          models.reject { |model| targets[model].nil? }
        end

        cap_filter.authorized_resources(authorizing_models).inject(Set.new) do |results, authorized_model|
          results.merge(unlocking_models_by_authorizing[authorized_model])
        end
      end

      private

      # Private: Recursively determine whether or not an ActiveRecord model has any currently `nil` parent relations.
      # This can happen when a model belongs to a Repository that is being deleted, for example, because we commonly
      # process post-destroy callbacks in background jobs.
      #
      # current_model - An ActiveRecord model or `nil` to verify.
      # current_relation - Relationship description consistent in format with that accepted by AREL's #includes
      #   method: either a Symbol, an Array, or a Hash.
      #
      # Returns `true` if `current_model` itself or any models accessible via the relationships described by
      # `current_relation` are `nil`.
      def any_nil_parents?(current_model, current_relation)
        return nil if current_model.nil?

        case current_relation
        when Symbol
          current_model.public_send(current_relation).nil?
        when Array
          current_relation.any? { |relation| any_nil_parents?(current_model, relation) }
        when Hash
          current_relation.any? do |(current_relation, child_relations)|
            next_model = current_model.public_send(current_relation)
            if next_model.nil?
              true
            else
              any_nil_parents?(next_model, child_relations)
            end
          end
        else
          raise "Unexpected element in PARENT_OBJECT_RELATIONS: #{current_relation.inspect}"
        end
      end

      def flatten_unlocking_models(unlocking_models)
        unlocking_models.flat_map do |unlocking_model|
          if unlocking_model.respond_to?(:flatten_as)
            unlocking_model.flatten_as
          else
            [unlocking_model]
          end
        end
      end

      def user_or_org_opted_out?(user_or_organization)
        user_or_organization&.profile_settings&.
          all_private_projects_opted_out_of_achievements_tracking?
      end
    end
  end
end
