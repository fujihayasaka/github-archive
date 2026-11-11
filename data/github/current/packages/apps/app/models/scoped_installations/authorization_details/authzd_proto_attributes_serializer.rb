# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    class AuthzdProtoAttributesSerializer

      sig { params(struct: Structs::V1, namespace: String).returns(T::Array[Authzd::Proto::Attribute]) }
      def self.generate(struct:, namespace:)
        attrs   = []
        version = struct.version

        prefix = [namespace, "authorization_details"].join(".")
        attrs << Authzd::Proto::Attribute.wrap("#{prefix}.version", version)

        prefix = [prefix, "v#{version}"].join(".")

        # Namespace all other properties under the version we're using.
        struct.serialize.each_pair do |prop_name, prop_value|
          next unless prop_value.is_a?(Hash)

          case prop_name
          when "selections", "subject_ids"
            prop_value.each_pair do |resource_type, value|
              attrs << Authzd::Proto::Attribute.wrap("#{prefix}.#{prop_name}.#{resource_type}", value)
            end
          when "subject_types_and_actions"
            prop_value.each_pair do |resource_type, permissions|
              next unless permissions.is_a?(Hash)

              permissions.each_pair do |resource, action|
                Permission.actions.each do |action_name, action_value|
                  next if action < action_value
                  attrs << Authzd::Proto::Attribute.wrap("#{prefix}.#{prop_name}.#{resource_type}.#{resource}.#{action_name}", true)
                end
              end
            end
          when "asymmetric"
            prop_value.each_pair do |resource_type, asymmetric|
              next unless asymmetric.is_a?(Hash) # sorbet...
              next if asymmetric.empty?

              attrs << Authzd::Proto::Attribute.wrap("#{prefix}.selections.#{resource_type}.asymmetric", true)

              # For each set of actions and subject ids in a given resource,
              # collect all relevant ids and send them as an attribute.
              #
              # For example:
              #
              #  { "repository" => { contents" => { "read" => [1, 2], "write" => [3, 4, 5] } }
              #
              # Would produce the following attributes:
              #
              #  <PREFIX>.authorization_details.v<VERSION>.asymmetric.repository.contents.read
              #  => [1, 2, 3, 4, 5]
              #
              #  <PREFIX>.authorization_details.v<VERSION>.asymmetric.repository.contents.write
              #  => [3, 4, 5]
              #
              # Because 'write' grants 'read' access so we combine them for
              # easier reasoning.
              #
              # Another example:
              #
              #  { "repository" => { contents" => { "write" => [3, 4, 5] } }
              #
              # Would produce the following attributes:
              #
              #  <PREFIX>.authorization_details.v<VERSION>.asymmetric.repository.contents.read
              #  => [3, 4, 5]
              #
              #  <PREFIX>.authorization_details.v<VERSION>.asymmetric.repository.contents.write
              #  => [3, 4, 5]
              #
              # Even though we did not explicitly grant 'read' access,
              # 'write' access implicitly grants 'read' access. This makes it
              # easier to reason about when writing authzd policies.

              asymmetric.each_pair do |resource, actions_and_subject_ids|
                # Setup each Hash with read, write, and admin keys.
                Permission.actions.keys.each do |action_name|
                  actions_and_subject_ids[action_name.to_s] ||= []
                end

                actions_and_subject_ids.each_pair do |action, subject_ids|
                  ids = subject_ids

                  # Collect all of the actions that are 'beneath' the currect
                  # action and it to the list.
                  #
                  # Example: 'write' collects 'read' and 'write' actions.
                  Permission.actions.keys.each do |key|
                    next if T.must(Permission.actions[key]) <= T.must(Permission.actions[action])
                    ids += actions_and_subject_ids[key]
                  end

                  if ids.any?
                    attrs << Authzd::Proto::Attribute.wrap("#{prefix}.#{prop_name}.#{resource_type}.#{resource}.#{action}", ids.uniq.sort)
                  end
                end
              end
            end
          else
            raise "Unknown property: #{prop_name}"
          end
        end

        attrs
      end
    end
  end
end
