# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      # This adds Node and Global ID features to GraphQL Object Types
      #
      module Node
        class InvalidGlobalIDPath < StandardError; end

        class InvalidTemplateError < StandardError; end

        class MissingCreatedAtError < StandardError; end

        # this is a snapshot of licenses from the License::IDS_TO_LICENSES constant, which all have legacy GlobalIDs.
        # This enshrines these to ensure we keep them on the old ID format during rollout.  If any new license's
        # are added to License::IDS_TO_LICENSES they will get the new format (since they aren't in this list, and
        # shouldn't be added here)
        LEGACY_IDS_TO_LICENSES = Set[
          "no-license", "other", "agpl-3.0", "apache-2.0", "artistic-2.0", "bsd-2-clause", "bsd-3-clause",
          "cc0-1.0", "epl-1.0", "gpl-2.0", "gpl-3.0", "isc", "lgpl-2.1", "lgpl-3.0", "mit", "mpl-2.0",
          "unlicense", "osl-3.0", "ofl-1.1", "wtfpl", "ms-pl", "ms-rl", "bsd-3-clause-clear", "afl-3.0",
          "lppl-1.3c", "eupl-1.1", "cc-by-4.0", "cc-by-sa-4.0", "zlib", "bsl-1.0", "ncsa", "ecl-2.0",
          "postgresql", "epl-2.0", "upl-1.0", "eupl-1.2", "0bsd", "cecill-2.1", "odbl-1.0", "bsd-4-clause",
          "vim", "mit-0"]

        # Main API for Object Types to implement the Node Interface
        #
        # Types should avoid implementing node manually and defining an ID field
        # and instead use this method which does 3 things:
        #
        #   - Implement the Node interface
        #   - Define an `id` field
        #   - Define the format and generation of the Global ID for the given type
        #
        # Each template must be composed of:
        #
        #   - A string prefix, used for disambiguating this template
        #   - Any number of variables (`{some_variable}`), containing the identifying information for the object.
        #     It should include the object's database ID and any other IDs required for future multi-datacenter routing
        #     (For example, the organization ID or user ID associated with the object.)
        #
        # Under the hood, the template is only used as a specification. Instead of actually constructing a string:
        #
        #   - The string prefix is converted to an _index_ of possible templates for this object type
        #   - The variable _values_ are put into an array
        #   - Then, those values are MessagePacked and base64-encoded
        #
        # This keeps IDs as small as possible while preserving all the necessary identifying information.
        #
        # To parse an ID generated this way:
        #
        #   - Split the `as:` abbreviation from base64-encoded ID
        #   - Use the abbreviation to lookup a GraphQL Object type (see `Platform::Helpers::GlobalId.expand_type_name(...)`)
        #   - Decode the base64-encoded ID, and unpack it with MessagePack
        #     - It should return an array of which the first member is an integer
        #   - The first member is an index identifying the template to use for the current ID (from among `templates` below)
        #   - The other members are values for the variables, in order, in that template
        #
        # In that system:
        #
        #   - The prefix isn't actually present in the ID -- instead, only its index in the list of path templates is present.
        #   - The name of variables is only used for making sure the that the returned hash matches the template
        #   - The template is used to hold the prefix and variable names, but it's never expanded into a string
        #   - The _order_ of `templates` passed to this method must be stable: if it changes, then the `index` encoded
        #     in existing IDs will be wrong.
        #
        # @param templates [Array<Array<Symbol>>]
        # @param ready_date [nil, String] is the date when this ID will be ready to be used (e.g., '1970-01-01').
        #    A `nil` value will result in this Node having legacy IDs.
        # @param as [String] is an abbreviation (all caps) for prefixing this object's Global IDs. (Must be unique among types.)
        # @param block Called when an ID must be generated for the given object.
        #    It should return a hash containing `prefix:`, matching the path template, and keys for any variables in the template. #
        def implements_node(templates:, as:, ready_date:, uses_database_id: true, allow_longer_prefix: false, allow_nil_for: [], &block)
          prefixes = []

          templates.each do |t|
            if !(t.is_a?(Array) && t.all? { |part| part.is_a?(Symbol) && part.to_s.match?(/\A[a-z0-9_]+\Z/) })
              raise InvalidTemplateError, "Invalid template for #{self.graphql_name}: #{t.inspect}, must contain all lower-case Symbols" # rubocop:disable GitHub/UsePlatformErrors
            end

            if t.size < 2
              raise InvalidTemplateError, "Template must include at least a prefix and one variable name (for #{self.graphql_name}: #{t})"  # rubocop:disable GitHub/UsePlatformErrors
            end

            if t.any? { |part| part == :prefix }
              raise InvalidTemplateError, "`prefix:` is reserved for matching the prefix of the template, it's not a valid variable name (in #{self.graphql_name}: #{t.inspect})" # rubocop:disable GitHub/UsePlatformErrors
            end

            if t.uniq != t
              raise InvalidTemplateError, "Templates can't have duplicate names (in #{self.graphql_name}: #{t})" # rubocop:disable GitHub/UsePlatformErrors
            end

            if uses_database_id && t.last != :id && t.last != "#{self.graphql_name.underscore}_id".to_sym
              raise InvalidTemplateError, "Template's last variable must be named `:id` or `:#{self.graphql_name.underscore}_id` (for #{self.graphql_name}: #{t})" # rubocop:disable GitHub/UsePlatformErrors
            end

            prefixes << t.first
          end

          uniq_prefixes = prefixes.uniq
          duplicate_prefixes = uniq_prefixes.select { |prefix| prefixes.count(prefix) > 1 }
          if duplicate_prefixes.any?
            raise InvalidTemplateError, "Invalid templates for #{self.graphql_name}: Can't register templates with duplicate prefixes (check #{duplicate_prefixes.map(&:inspect).join(", ")})" # rubocop:disable GitHub/UsePlatformErrors
          end

          # This variable is set to ensure that no public object calls
          # implements Platform::Interfaces::Node directly.
          @called_from_implements_node = true

          implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

          Platform::Helpers::GlobalId.register_short_name(as, graphql_name, allow_longer: allow_longer_prefix)

          global_id_field :id, description: generate_placeholder_description # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

          @global_id_templates = templates
          @global_id_expander = block
          @global_id_ready_date = Date.parse(ready_date) if ready_date
          @uses_database_id = uses_database_id
          @allow_nil_for = allow_nil_for
        end

        def called_from_implements_node?
          !!@called_from_implements_node
        end

        attr_reader :global_id_templates

        attr_reader :global_id_ready_date


        # Synchronous version of `async_global_id`. Avoid calling this from a GraphQL
        # Execution context
        # @param object [Object] the expected domain object to be resolved for this type
        # @return [nil, String] If the type implements node, returns the global ID for the given object
        def global_id(object)
          async_global_id(object).sync # rubocop:disable GitHub/DontSyncInsideFields
        end

        # Returns the Global ID for a particular object.
        # @param object [Object] the expected domain object to be resolved for this type
        # @return [Promise<nil, String>] If the type implements node, returns the global ID for the given object
        def async_global_id(object)
          if !@global_id_templates || !@global_id_expander
            return Promise.resolve(nil)
          end

          Promise.resolve(@global_id_expander.call(object)).then do |variables|
            ensure_hash!(variables)

            prefix = variables.delete(:prefix)

            template = nil
            template_idx = 0
            @global_id_templates.each do |t|
              if t.first == prefix
                template = t
                break
              end
              template_idx += 1
            end

            if template.nil?
              raise(Platform::Errors::Internal, "No matching template for prefix #{prefix.inspect}, available templates: #{@global_id_templates}")
            end

            parts = []
            template.each do |part|
              if parts.empty?
                parts << template_idx # it's the prefix
              elsif (value = variables[part]) || @allow_nil_for.include?(part)
                parts << value
              else
                raise InvalidGlobalIDPath, "Missing or nil value for global id path variable `#{part}` in #{self} (add it to `allow_nil_for: [...]` if `nil` is expected here)" # rubocop:disable GitHub/UsePlatformErrors
              end
            end

            if @uses_database_id && variables[template.last] != object.id
              raise InvalidGlobalIDPath, "Value for global ID path variable `:#{template.last}` (#{variables[template.last]}) does not match object ID (#{object.id})" # rubocop:disable GitHub/UsePlatformErrors
            end

            id = MessagePack.pack(parts)

            # Remove the `=` padding at the end of the strings, to make them shorter. (It can be parsed without that padding.)
            encoded_id = Base64
              .urlsafe_encode64(id)
              .sub(/=+\Z/, "")

            "#{Platform::Helpers::GlobalId.compress_type_name(self.graphql_name)}#{Platform::Helpers::GlobalId::DELIMITER}#{encoded_id}"
          end
        end

        # Should this type return the new type defined global IDs or fallback to the model legacy gid?
        #
        # The main way to know if this type should use the next global ids
        # is to use our ready_date concept with domain objects that have a created_at
        # attribute or method. If more complex logic is required, this method
        # can be overridden.
        #
        # @param object [Object] the expected domain object to be resolved for this type
        # @return Boolean
        def use_next_id?(object)
          return false if GitHub.enterprise?
          return false unless @global_id_templates

          if Rails.env.test? && TestEnv.test_all_features? && !Objects::Base::Node.new_global_id_flag_skipped?
            # This is for testing new IDs _before_ their ready date arrives, in the `github-all-features` build
            return true
          end

          # setting ready date to nil disables next_global_id
          return false unless @global_id_ready_date

          if object.class.respond_to?(:column_names) && object.class.column_names.include?("created_at") && !object.respond_to?(:created_at)
            error_message = <<~MSG
              #{object.class} doesn't respond to the created_at method, but it should.

              This object has a created_at column, but doesn't respond to the created_at method.
              This is most likely due to the use of the `.select` or `.pluck` method to only pick
              out certain attrs. Kindly add :created_at so the proper GlobalID can be selected.
            MSG

            if Rails.env.production?
              Failbot.report_trace(MissingCreatedAtError.new(error_message))
            else
              raise MissingCreatedAtError, error_message # rubocop:disable GitHub/UsePlatformErrors
            end
          end

          # this object is behind a FF with only one person, so it's safe to release for everything.
          # It does respond to `created_at` but we will not be using that for the rollout,
          # that is why this block is before the below if/elsif.
          if object.is_a?(Octoshift::RepositoryMigration)
            return true
          end

          if object.is_a?(::User) && object.id == 90472703 # next-global-id-user test user for Actions pre-release.
            return true
          end

          if object.is_a?(::Organization) && object.id == 90404679 # next-global-id test org for Actions pre-release.
            return true
          end

          # This block is here so we can test out the new format for newly created
          # repos in the github org before the actual ready date goes GA.
          #
          # Since these repos will be released with the new format ID, this code needs to
          # stay until we fully deprecate the old ID format.
          if object.is_a?(::Repository) && object.owner_id && (object.github_owned? || object.owner_display_login == "bbq-beets") && object.created_at >= DateTime.parse(Platform::Helpers::GlobalId::COHORT_2)
            return true
          end

          created_at = if object.respond_to?(:created_at) && object.created_at
            object.created_at
          elsif object.is_a?(DependencyGraph::Manifest)
            object.async_repository.sync.created_at #rubocop:disable GitHub/DontSyncInsideFields
          elsif object.is_a?(::Blob) || object.is_a?(::Git::Ref) || object.is_a?(::Tree)
            object.repository.created_at
          elsif object.is_a?(::License)
            return !LEGACY_IDS_TO_LICENSES.include?(object.key)
          elsif object.is_a?(::RepositoryCodeOfConduct)
            object.repository.created_at
          elsif object.is_a?(Platform::Models::PushAllowance)
            object.branch_protection_rule.created_at
          elsif object.is_a?(::CombinedStatus) && object.platform_type_name == "Status"
            object.repository.created_at
          elsif object.is_a?(::CombinedStatus) && object.platform_type_name == "StatusCheckRollup"
            # Because the check is dependent on the repo
            object.repository.created_at
          elsif object.is_a?(Platform::Models::NotificationThread)
            first_item = object.sorted_items&.first
            datetime = safely_parse_date(first_item["created_at"]) if first_item
            return false unless datetime
            datetime
          elsif object.is_a?(::CodeOfConduct)
            return false
          elsif object.is_a?(Octoshift::MigrationSource)
            # this object is behind a FF with only one person, so it's safe to release for everything.
            return true
          elsif object.is_a?(Marketplace::Category)
            return false
          elsif object.is_a?(::MigratableResource)
            return true
          elsif object.is_a?(::Platform::Models::PullRequestCommitCommentThread)
            object.async_pull_request.sync.created_at #rubocop:disable GitHub/DontSyncInsideFields
          elsif object.is_a?(::RepositoryDependabotAlertsThread)
            object.repository.created_at
          elsif object.is_a?(Business::OIDCProvider)
            return true
          elsif object.is_a?(::Platform::Models::Patch)
            return true
          elsif object.is_a?(::TeamDashboard)
            return true
          elsif object.is_a?(::Platform::Models::ProjectItemFieldGroup)
            return true
          else
            return false
          end

          created_at = Date.parse(created_at) if created_at.is_a?(String)
          created_at >= @global_id_ready_date
        end

        def self.skipping_new_global_id_flag
          # If we encounter nested calls to this method,
          # then we'll need a counter.
          start_skipping_new_global_id_flag
          yield
        ensure
          stop_skipping_new_global_id_flag
        end

        def self.start_skipping_new_global_id_flag
          @new_global_id_flag_skipped = true
        end

        def self.stop_skipping_new_global_id_flag
          @new_global_id_flag_skipped = false
        end

        def self.new_global_id_flag_skipped?
          @new_global_id_flag_skipped
        end

        # Has this object been setup with a ready date?
        # Used to determine whether we can show the next global ID if
        # the user requested it.
        def has_ready_global_id?
          !@global_id_ready_date.nil?
        end

        private

        # This method is used to populate a minimal description for the `id` field on GraphQL objects where the
        # subclass has not decided to add their own fields. This can be overriden by adding `field :id` on the
        # subclass which will
        def generate_placeholder_description
          if self.respond_to?(:type_name)
            "The Node ID of the #{self.type_name} object"
          elsif self.respond_to?(:class_name)
            "The Node ID of the #{self.class_name} object"
          elsif self.respond_to?(:type_class) && self.type_class.respond_to?(:graphql_name)
            "The Node ID of the #{self.type_class.graphql_name} object"
          else
            "The Node ID of this object"
          end
        end

        def ensure_hash!(values)
          if !values.is_a?(Hash)
            # rubocop:disable GitHub/UsePlatformErrors
            raise InvalidGlobalIDPath, "The `implements_node` block returned #{values} which is not a valid hash. Make sure to return a hash that contains values for every variable in the path."
          end
        end

        # Safely parses a given value into a date/time without throwing an error.
        def safely_parse_date(created_at)
          begin
            if [DateTime, Date, Time].include?(created_at.class)
              created_at
            elsif created_at.is_a?(String)
              Date.parse(created_at)
            elsif created_at.is_a?(Integer)
              Time.at(created_at)
            end
          rescue Date::Error
            nil
          end
        end
      end
    end
  end
end
