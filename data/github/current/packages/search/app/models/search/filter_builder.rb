# typed: true
# frozen_string_literal: true

module Search

  # The FilterBuilder is a helper class that handles the grunt work of
  # transforming values stored in the qualifier terms Hash into actual, usable
  # Filter instances.
  class FilterBuilder
    attr_reader :qualifiers

    # Create a new FilterBuilder.
    #
    # qualifiers - The Hash of parsed qualifier terms.
    #
    def initialize(qualifiers)
      @qualifiers = qualifiers
    end

    # Build the positive and negative PrefixFilter instances.
    #
    # If the values stored in the filter field hashes are not in the correct
    # format, then a block can be given to this method. The values in the
    # filter field hashes will be passed to this block, and the returned
    # values from the block will be used in the generated filters.
    #
    # field - The filter field name as a Symbol.
    # args  - An optional list of filter field names as found in the
    #         positive/negative filter hashes.
    #
    # Returns a two element Array containing the positive Filter and the
    # negative Filter.
    def prefix_filter(field, *args, &block)
      T.unsafe(self).build(Filters::PrefixFilter, field, *args, &block)
    end

    # Build the positive and negative HashFilter instances.
    #
    # If the values stored in the filter field hashes are not in the correct
    # format, then a block can be given to this method. The values in the
    # filter field hashes will be passed to this block, and the returned
    # values from the block will be used in the generated filters.
    #
    # field - The filter field name as a Symbol.
    # args  - An optional list of filter field names as found in the
    #         positive/negative filter hashes.
    #
    # Returns a two element Array containing the positive Filter and the
    # negative Filter.
    def sha_filter(field, *args, &block)
      T.unsafe(self).build(Filters::ShaFilter, field, *args, &block)
    end

    # Build the positive and negative QueryFilter instances.
    #
    # If the values stored in the filter field hashes are not in the correct
    # format, then a block can be given to this method. The values in the
    # filter field hashes will be passed to this block, and the returned
    # values from the block will be used in the generated filters.
    #
    # field - The filter field name as a Symbol.
    # args  - An optional list of filter field names as found in the
    #         positive/negative filter hashes.
    #
    # Returns a two element Array containing the positive Filter and the
    # negative Filter.
    def query_filter(field, *args, &block)
      T.unsafe(self).build(Filters::QueryFilter, field, *args, &block)
    end

    # Build the positive and negative RangeFilter instances.
    #
    # If the values stored in the filter field hashes are not in the correct
    # format, then a block can be given to this method. The values in the
    # filter field hashes will be passed to this block, and the returned
    # values from the block will be used in the generated filters.
    #
    # field - The filter field name as a Symbol.
    # args  - An optional list of filter field names as found in the
    #         positive/negative filter hashes.
    #
    # Returns a two element Array containing the positive Filter and the
    # negative Filter.
    def range_filter(field, *args, &block)
      T.unsafe(self).build(Filters::RangeFilter, field, *args, &block)
    end

    # Build the positive and negative DateRangeFilter instances.
    #
    # If the values stored in the filter field hashes are not in the correct
    # format, then a block can be given to this method. The values in the
    # filter field hashes will be passed to this block, and the returned
    # values from the block will be used in the generated filters.
    #
    # field - The filter field name as a Symbol.
    # args  - An optional list of filter field names as found in the
    #         positive/negative filter hashes.
    #
    # Returns a two element Array containing the positive Filter and the
    # negative Filter.
    def date_range_filter(field, *args, &block)
      T.unsafe(self).build(Filters::DateRangeFilter, field, *args, &block)
    end

    # Build the positive and negative KeywordRangeFilter instances.
    #
    # This filter constructs lexicographic range queries for keyword-like fields
    # (including flattened fields) and ensures both lower and upper bounds are present.
    def keyword_range_filter(field, *args, &block)
      T.unsafe(self).build(Filters::KeywordRangeFilter, field, *args, &block)
    end

    # Build the positive and negative KeywordDateRangeFilter instances.
    #
    # This filter constructs lexicographic date range queries for keyword-like fields
    # (including flattened fields) and ensures both lower and upper bounds are present.
    def keyword_date_range_filter(field, *args, &block)
      T.unsafe(self).build(Filters::KeywordDateRangeFilter, field, *args, &block)
    end

    # Build the positive and negative TermFilter instances.
    #
    # If the values stored in the filter field hashes are not in the correct
    # format, then a block can be given to this method. The values in the
    # filter field hashes will be passed to this block, and the returned
    # values from the block will be used in the generated filters.
    #
    # field - The filter field name as a Symbol.
    # args  - An optional list of filter field names as found in the
    #         positive/negative filter hashes.
    #
    # Returns a two element Array containing the positive Filter and the
    # negative Filter.
    def term_filter(field, *args, &block)
      T.unsafe(self).build(Filters::TermFilter, field, *args, &block)
    end

    # Build a special TermFilter for labels.
    #
    # This label filter allows a commma-delimited list of labels to be interpreted
    # as an OR in the lucene query DSL, rather than the default AND
    def label_filter(field, *args)
      filter = T.unsafe(self).enumerated_term_filter(field, *args)
      filter.map_bool_collection { |label| label.downcase }
      filter
    end

    # Build a Custom Properties filter.
    #
    # This filter groups together all the custom properties filters
    # Instead of providing a list of keys, this method must be called with a regex
    # because the keys are dynamic for the defined custom properties
    def custom_properties_filter(field, key_regex, **opts)
      opts[:field] = field
      opts[:key_regex] = key_regex
      opts[:qualifiers] = qualifiers

      # We never want to OR custom properties because they are distinct conditions.
      # E.g. "props.a:1 props.b:2" must always AND ["a:1", "b:2"]
      # because `props.a` and `props.b` are 2 separate qualifiers to the user,
      # even though they are translated into the same `custom_properties` ES field
      opts[:execution] = :and

      Filters::CustomPropertyFilter.new(opts)
    end

    def repos_no_filter(field, key_regex, **opts)
      opts[:field] = field
      opts[:key_regex] = key_regex
      opts[:qualifiers] = qualifiers
      opts[:execution] = :and

      Filters::ReposNoFilter.new(opts)
    end

    # Build a special TermFilter that supports the OR comma syntax.
    #
    # This label filter allows a commma-delimited list of labels to be interpreted
    # as an OR in the lucene query DSL, rather than the default AND
    def enumerated_term_filter(field, *args)
      opts = args.extract_options!

      opts[:field] = field
      opts[:keys]  = args
      opts[:qualifiers] = qualifiers

      Filters::EnumeratedTermFilter.new(opts)
    end

    # Build the positive and negative ActionFilter instances.
    #
    # If the values stored in the filter field hashes are not in the correct
    # format, then a block can be given to this method. The values in the
    # filter field hashes will be passed to this block, and the returned
    # values from the block will be used in the generated filters.
    #
    # field - The filter field name as a Symbol.
    # args  - An optional list of filter field names as found in the
    #         positive/negative filter hashes.
    #
    # Returns a two element Array containing the positive Filter and the
    # negative Filter.
    def action_filter(field, *args, &block)
      T.unsafe(self).build(Filters::ActionFilter, field, *args, &block)
    end

    # Build a MarketplaceListingFilter. Includes Marketplace::Listing.
    #
    # current_user - The current logged in User.
    #
    # Returns a MarketplaceListingFilter instance.
    def marketplace_listing_filter(current_user, is_dsa_compliant: false)
      Search::Filters::MarketplaceListingFilter.new(qualifiers: qualifiers,
                                                    current_user: current_user,
                                                    is_dsa_compliant: is_dsa_compliant)
    end

    # Build a RepositoryFilter.
    #
    # current_user - The current logged in User.
    # repo_id      - Restrict the filter to just this repository ID
    # resource     - Restrict the filter to repositories where the user has
    #                access to the specified resource.
    # cap_filter   - Filter object to check permissions, if available
    #                This is an alternative to passing user_session & ip to create a cap_filter inside.
    # ip           - A String representing the user's IP address from which the
    #                search originated.
    # field        - The name of the field in the index that holds the
    #                repository ID. Defaults to :repo_id.
    # limit_to_repo_ids - An optional array of repository IDs to limit the search to.
    # allow_contributed_by_filter - Allow the `contributed-by:` filter to be used.
    #
    # Returns a RepositoryFilter instance.
    def repository_filter(current_user, repo_id = nil, resource = nil, cap_filter: nil, user_session: nil, ip: nil, field: :repo_id, candidate_private_repo_ids: nil, limit_to_repo_ids: nil, allow_contributed_by_filter: false)
      Search::Filters::RepositoryFilter.new \
          qualifiers:,
          current_user:,
          cap_filter:,
          user_session:,
          ip:,
          repo_id:,
          resource:,
          field:,
          candidate_private_repo_ids:,
          limit_to_repo_ids:,
          allow_contributed_by_filter:
    end

    # Build a ConditionalRepositoryFilter.
    #
    # current_user - The current logged in User.
    # repo_id      - Restrict the filter to just this repository ID
    # field        - The name of the field in the index that holds the
    #                repository ID. Defaults to :repo_id.
    # resource     - Restrict the filter to repositories where the user has
    #                access to the specified resource. Defaults to "content"
    # cap_filter   - Filter object to check permissions, if available
    #                This is an alternative to passing user_session & ip to create a cap_filter inside.
    # ip           - A String representing the user's IP address from which the
    # limit_to_repo_ids - An optional array of repository IDs to limit the search to.
    # execution    - a symbol containing the bool execution context -> :and, :or. Default to :and
    #
    # Returns a ConditionalRepositoryFilter instance.
    def conditional_repository_filter(
      current_user,
      repo_id = nil,
      field: :repo_id,
      resource: nil,
      cap_filter: nil,
      user_session: nil,
      ip: nil,
      limit_to_repo_ids: nil,
      execution: :and
    )
      Search::Filters::ConditionalRepositoryFilter.new \
          qualifiers:,
          current_user:,
          field:,
          repo_id:,
          resource:,
          cap_filter:,
          user_session:,
          ip:,
          limit_to_repo_ids:,
          execution:
    end

    # Builds the best-fit filter for the given qualifiers.
    #
    # It applies the owner_id optimizations if possible, otherwise falls back to repository_filter
    # Use only from indexes that include `owner_id` and `visibility`,
    # keep using `repository_filter` for indexes that only include `repo_id`.
    def owner_repo_filter(current_user, cap_filter: nil, skip_permission_check: false, field: :repo_id, limit_to_repo_ids: nil)
      Search::Filters::OwnerRepoFilter.new \
        qualifiers:,
        current_user:,
        cap_filter:,
        skip_permission_check:,
        field:,
        limit_to_repo_ids:
    end

    # Build a RegistryPackagesFilter.
    #
    # current_user - The current logged in User.
    # repo_id      - Restrict the filter to just this repository ID
    # resource     - Restrict the filter to repositories where the user has
    #                access to the specified resource.
    #
    # Returns a RegistryPackagesFilter instance.
    def registry_packages_filter(current_user, owner_id = nil, repo_id = nil, resource = nil, user_session: nil, package_type: nil, only_deleted_packages: false, excluded_packages: [])
      Search::Filters::RegistryPackagesFilter.new \
          qualifiers: qualifiers,
          current_user: current_user,
          user_session: user_session,
          owner_id: owner_id,
          repo_id: repo_id,
          resource: resource,
          package_type: package_type,
          only_deleted_packages: only_deleted_packages,
          excluded_packages: excluded_packages
    end

    # Build a RegistryFilter.
    #
    # current_user - The current logged in User.
    # repo_id      - Restrict the filter to just this repository ID
    # resource     - Restrict the filter to repositories where the user has
    #                access to the specified resource.
    #
    # Returns a RegistryFilter instance.
    def registry_filter(current_user, owner_id = nil, repo_id = nil, resource = nil, user_session: nil, package_type: nil, only_deleted_packages: false, excluded_packages: [])
      Search::Filters::RegistryFilter.new \
          qualifiers: qualifiers,
          current_user: current_user,
          user_session: user_session,
          owner_id: owner_id,
          repo_id: repo_id,
          resource: resource,
          package_type: package_type,
          only_deleted_packages: only_deleted_packages,
          excluded_packages: excluded_packages
    end

    # Build a ProjectOwnerFilter
    #
    # owner_id - Restrict the filter to just this owner ID
    # owner_type - The type of owner the ID maps to
    #
    #
    # Returns a ProjectOwnerFilter instance.
    def project_owner_filter(owner_id:, owner_type:)
      Search::Filters::ProjectOwnerFilter.new \
          qualifiers: qualifiers,
          owner_id: owner_id,
          owner_type: owner_type
    end

    # Build a ProjectFilter
    #
    # owner_id     - The ID of the org or user whose projects we're searching.
    # current_user - The current logged in User.
    # scoped       - Whether to include public/private repo projects within a owner level search.
    #
    # Returns a ProjectFilter.
    def project_filter(owner_id, current_user, scoped = false)
      Search::Filters::ProjectFilter.new(
        qualifiers: qualifiers,
        owner_id: owner_id,
        current_user: current_user,
        scoped: scoped
      )
    end

    # Build a ProjectLinkedRepositoryFilter
    #
    # field - The filter field name as a Symbol.
    # args  - An optional list of filter field names as found in the
    #         qualifiers hash
    #
    # Returns the UserFilter.
    def project_linked_repository_filter(field, *args)
      T.unsafe(self).build(Filters::ProjectLinkedRepositoryFilter, field, *args)
    end

    # Build a StarSearchFilter
    #
    # current_user - The current logged in user
    #
    # Returns a StarSearchFilter instance
    def star_filter(current_user, star_user)
      Search::Filters::StarSearchFilter.new \
          qualifiers: qualifiers,
          current_user: current_user,
          star_user: star_user
    end

    # Build a GistFilter.
    #
    # current_user - The current logged in User.
    #
    # Returns a RepositoryFilter instance.
    def gist_filter(current_user)
      Search::Filters::GistFilter.new \
          qualifiers: qualifiers,
          current_user: current_user
    end

    def enterprise_managed_user_filter(business_id)
      Search::Filters::EnterpriseManagedUserFilter.new(business_id: business_id)
    end

    def enterprise_filter(scope_to_ids)
      Search::Filters::EnterpriseFilter.new(
        enterprise_ids: scope_to_ids
      )
    end

    # Build a UserFilter instance. The values from the positive and negative
    # filter field hashes should be user login Strings. These logins are used
    # to lookup the user in the database and retrieve the ID.
    #
    # field - The filter field name as a Symbol.
    # args  - An optional list of filter field names as found in the
    #         qualifiers hash
    #
    # Returns the UserFilter.
    def user_filter(field, *args)
      T.unsafe(self).build(Filters::UserFilter, field, *args)
    end

    # Build a Discussions::CategoryFilter instance. The values from the positive and
    # negative filter field hashes should be category name Strings. These names
    # are used to lookup the category in the database and retrieve the ID.
    #
    # field - The filter field name as a Symbol.
    # args  - An optional list of filter field names as found in the
    #         qualifiers hash
    #
    # Returns the Discussions::CategoryFilter.
    def discussions_category_filter(field, *args)
      T.unsafe(self).build(Filters::Discussions::CategoryFilter, field, *args)
    end

    # Build a Discussions::AnsweredFilter instance. This filter handles the "answered"
    # qualifier for discussions by including discussions that are answered but
    # excluding those that are verified.
    #
    # field - The filter field name as a Symbol.
    # args  - An optional list of filter field names as found in the
    #         qualifiers hash
    #
    # Returns the Discussions::AnsweredFilter.
    def discussions_answered_filter(field, *args)
      T.unsafe(self).build(Filters::Discussions::AnsweredFilter, field, *args)
    end

    # Build a TeamFilter.
    #
    # current_user - The current logged in User.
    # field - The document field containing the team IDs.
    # args  - An optional list of filter field names as found in the
    #         qualifiers list.
    #
    # Returns a TeamFilter instance.
    def team_filter(current_user, field, *args, execution: :plain)
      Search::Filters::TeamFilter.new \
          field: field,
          keys: args,
          qualifiers: qualifiers,
          current_user: current_user,
          execution: execution
    end

    def user_review_request_filter(field, *args)
      T.unsafe(self).build(Filters::UserReviewRequestFilter, field, *args)
    end

    def review_request_filter(field, *args)
      T.unsafe(self).build(Filters::ReviewRequestFilter, field, *args)
    end

    # Build an InvolvesFilter instance. This filter type operates on multiple
    # fields using the same filter construct for each field. The values from
    # the positive and negative filter field hashes should be user login
    # Strings. These logins are used to lookup the user in the database and
    # retrieve the ID.
    #
    # fields - The Array of fields to filter on.
    # args   - An optional list of filter field names as found in the
    #          qualifiers hash
    #
    # Returns the InvolvesFilter.
    def involves_filter(fields, *args)
      T.unsafe(self).build(Filters::InvolvesFilter, fields, *args)
    end

    # Create filters for language terms. The field name for the filter is
    # required. Also required is the method name to call on the
    # Linguist::Language for obtaining the correct language value to filter
    # on.
    #
    # field  - The filter field name as a Symbol.
    # method - The Linguist::Language method name as a Symbol.
    # args   - An optional list of filter field names as found in the
    #          positive/negative filter hashes.
    #
    # Returns a two element Array containing the positive Filter and the
    # negative Filter.
    def language_filter(field, method, *args)
      method = method.to_sym

      T.unsafe(self).build(Filters::EnumeratedTermFilter, field, *args) do |language|
        case language
        when String
          alias_name = language.downcase.gsub(/\s/, "-")
          Linguist::Language[alias_name].try(method)
        when Linguist::Language
          language.try(method)
        end
      end
    end

    # Build a special TermFilter for spoken language fields. Expected the search index to include
    # the two-character language code, e.g., "en" for English. Allows filtering by either the
    # two-character code or its English name, e.g., "Spanish". Case insensitive.
    #
    # This filter allows a comma-delimited list of languages to be interpreted
    # as an OR in the lucene query DSL, rather than the default AND.
    def spoken_language_filter(field, *args)
      filter = T.unsafe(self).enumerated_term_filter(field, *args)
      filter.map_bool_collection do |lang|
        lang_code = if lang.size > 2
          lang_info = Trending::SpokenLanguageFinder.preference_selections.detect do |(name, _code)|
            names = if name.include?(",") # e.g., "Spanish, Castilian"
              name.split(",").map(&:strip)
            else
              [name]
            end
            names.map(&:downcase).include?(lang.downcase)
          end
          lang_info ? lang_info[1] : lang
        else
          lang
        end
        lang_code.downcase
      end
      filter
    end

    # Create filters for license terms. The field name for the filter is
    # required.
    #
    # field  - The filter field name as a Symbol.
    # args   - An optional list of filter field names as found in the
    #          positive/negative filter hashes.
    #
    # Returns a two element Array containing the positive Filter and the
    # negative Filter.
    def license_filter(field, *args)
      Search::Filters::LicenseFilter.new(
          field: field,
          keys: args,
          qualifiers: qualifiers,
      )
    end

    # Create a filter for milestone titles and/or numbers.
    def milestone_filter(*args)
      Search::Filters::MilestoneFilter.new \
          keys: args,
          qualifiers: qualifiers
    end

    # Create a filter for milestone numbers.
    def milestone_number_filter(*args)
      Search::Filters::MilestoneNumberFilter.new \
          keys: args,
          qualifiers: qualifiers
    end

    def state_reason_filter(*args, accept_multiple_reasons: false, execution: :plain)
      Search::Filters::StateReasonFilter.new \
        keys: args,
        accept_multiple_reasons:,
        execution:,
        qualifiers: qualifiers
    end

    def issue_type_name_filter(*keys)
      field = :issue_type_name
      keys = [:issue_type] if keys.empty?
      filter = T.unsafe(self).enumerated_term_filter(field, *keys)
      filter.map_bool_collection { |name| name.downcase }
      filter
    end

    # Create a filter for issue project numbers (supports Projects Classic and Projects Next)
    def issue_project_and_memex_project_filter(field, current_user:, execution: :and)
      Search::Filters::IssueProjectAndMemexProjectFilter.new(
        keys: [field],
        qualifiers: qualifiers,
        current_user: current_user,
        execution: execution
      )
    end

    def memex_project_exclusion_filter(memex_project_id:, repository_id:)
      Search::Filters::MemexProjectExclusionFilter.new(
        memex_project_id: memex_project_id,
        repository_id: repository_id
      )
    end

    def ids_to_exclude_filter(ids:)
      Search::Filters::IdsToExcludeFilter.new(ids_to_exclude: ids)
    end

    # Internal: Build the desired positive and negative Filter instances.
    # Required are the name of the filter field and the type of filter to
    # create.
    #
    # If the values stored in the filter field hashes are not in the correct
    # format, then a block can be given to this method. The values in the
    # filter field hashes will be passed to this block, and the returned
    # values from the block will be used in the generated filters.
    #
    # filter_class - The Filter class to instantiate.
    # field        - The filter field name as a Symbol.
    # args         - An optional list of filter field names as found in the
    #                positive/negative filter hashes.
    #
    # Examples
    #
    #   build( TermFilter, :label )
    #   #=> [positive_filter, negative_filter]
    #
    #   build( TermFilter, :user_id, :user ) { |login| User.find_by_login(login).try(:id) }
    #   #=> [positive_filter, negative_filter]
    #
    #   build( RangeFilter, :updated_at, :updated, :pushed )
    #   #=> [positive_filter, negative_filter]
    #
    # Returns a two element Array containing the positive Filter and the
    # negative Filter.
    def build(filter_class, field, *args, &block)
      opts = args.extract_options!

      opts[:field] = field
      opts[:keys]  = args
      opts[:qualifiers] = qualifiers

      filter = filter_class.new opts
      filter.map_bool_collection(&block)
      filter
    end

  end  # FilterBuilder
end  # Search
