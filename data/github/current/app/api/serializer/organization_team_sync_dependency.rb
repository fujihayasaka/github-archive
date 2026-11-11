# typed: true
# frozen_string_literal: true

module Api::Serializer::OrganizationTeamSyncDependency
  extend(T::Helpers)

  BATCH_SIZE = 1000

  requires_ancestor { Api::Serializer }

  # Creates a Hash to be serialized to JSON.
  #
  # group - group returned from group-syncer
  # Returns a Hash if the group is present.
  def group_hash(group, options = {})
    {
      group_id: group.id,
      group_name: group.name,
      group_description: group.description,
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # group - group returned from external groups
  #
  # Returns a Hash if the group is present.
  def external_group_hash(group, options = {})
    json = {
      group_id: group.id,
      group_name: group.display_name,
      updated_at: time(group.updated_at),
    }
    business = group&.provider&.business

    if options.is_a?(Hash) && options[:full_group_info]
      populate_external_group_details(json, group, options, business)
    end

    json
  end

  def populate_external_group_details(json, group, options, business)
    pagination_opts = options[:pagination]
    members = ExternalIdentity.by_provider(group.provider)
      .joins(:external_identity_group_memberships)
      .where(active: true, external_identity_group_memberships: { external_group_id: group.id })
      .select(:user_id)

    # Prefer users join on external_identities, rather than profiles join on external_identities
    json[:members] = []
    memberships_batches_count = 0

    if pagination_opts.present?
      memberships_batches_count = 1
      page = pagination_opts[:page].to_i
      per_page = pagination_opts[:per_page].to_i
      page = 1 if page < 1

      user_ids = members.pluck(:user_id)
      user_ids.uniq!

      # Fetch only the 4 columns needed for serialization, sort in Ruby.
      # Sorting in Ruby avoids an additional DB round-trip and is safe because
      # compare_record_sequence compares sorted ID arrays, not display name order.
      sorted_users = User.where(id: user_ids)
        .select(:id, :login, :display_name, :display_login)
        .to_a
        .sort_by { |u| u.display_name.to_s.downcase }

      # Slice the current page directly from the sorted array — no second
      # User.where query needed. Preload profiles onto the slice only,
      # keeping the profile query bounded to at most per_page records.
      paginated_users = sorted_users
        .slice((page - 1) * per_page, per_page) || []

      ActiveRecord::Associations::Preloader.new(
        records: paginated_users,
        associations: [:profile],
      ).call

      paginated_users.each do |user|
        json[:members] << {
          member_id: user.id,
          member_login: user.login_for_api(use: options[:serialize_login]),
          member_name: user.display_name,
          member_email: user.profile_email,
        }
      end

      # unscoping select to get a better performance from count
      if pagination_opts[:page].to_i == 1 && pagination_opts[:per_page].to_i > json[:members].count
        json[:members_count] = json[:members].count
      else
        json[:members_count] = members.unscope(:select).select("1").count
      end

    else
      user_ids = members.pluck(:user_id)
      user_ids.uniq!

      unless user_ids.empty?
        users = user_ids.each_slice(BATCH_SIZE).flat_map do |batch|
          User.where(id: batch).preload(:profile).to_a
        end

        users.each_slice(BATCH_SIZE) do |user_batch|
          memberships_batches_count += 1
          user_batch.each do |user|
            json[:members] << {
              member_id: user.id,
              member_login: user.login_for_api(use: options[:serialize_login]),
              member_name: user.display_name,
              member_email: user.profile_email,
            }
          end
        end
      end
    end

    json[:members].compact!

    GitHub.logger.info(
      "info.message" => "Processed #{memberships_batches_count} membership batches",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "group.id" => group.id,
      "business.id" => group.provider.business.id,
    )

    json[:teams] = []
    teams_batches_count = 0

    teams = Team.joins(:external_group_team)
      .where(id: options[:team_ids])
      .where(external_group_teams: { external_group_id: group.id })

    teams.find_in_batches(batch_size: BATCH_SIZE) do |teams_batch|
      teams_batches_count += 1
      teams_batch.each do |team|
        json[:teams] << {
          team_id: team.id,
          team_name: team.name,
        }
      end
    end

    json[:teams].compact!

    GitHub.logger.info(
      "info.message" => "Processed #{teams_batches_count} team batches",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "group.id" => group.id,
      "business.id" => group.provider.business.id,
    )

    json
  end

  # mapping - group_mapping
  # Returns a Hash if the mapping is present.
  def mapping_hash(mapping, options = {})
    {
      group_id: mapping.group_id,
      group_name: mapping.group_name,
      group_description: mapping.group_description,
      status: mapping.status,
      synced_at: mapping.synced_at,
    }
  end
end
