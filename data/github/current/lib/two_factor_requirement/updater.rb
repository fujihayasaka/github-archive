# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Updater
    # Public: Update the 2FA requirement status for a list of user IDs.
    #
    # user_ids - An Array of User IDs to update.
    # requirement_reason - The reason (TwoFactorRequirement::Reason) why this batch of users is required for two-factor authentication.
    # cohort - The cohort (int) that this batch of users belongs to. Optional.
    #
    # Returns nothing.
    def self.require_for_reason(user_ids:, requirement_reason:, cohort: nil, transaction_batch_size: 1000)
      raise ArgumentError, "requirement_reason is required" if requirement_reason.nil?
      return if user_ids.nil? || user_ids.empty?

      required_by = Time.now.utc.beginning_of_day + requirement_reason.grace_period
      update_count = 0

      # filters deleted and EMU users
      filtered_users_ids = User
        .batched_scope(:id, values: user_ids)
        .where("login NOT LIKE ? OR login IN (?)", "%\\_%", User::EnterpriseManagedDependency::INVALID_UNDERSCORE_LOGIN)
        .pluck(:id)

      filtered_users_ids.in_groups_of(transaction_batch_size, false) do |group|
        group_update_count = 0

        User.transaction do
          begin
            all_existing_metadata = TwoFactorRequirementMetadata.where(user_id: group)
            optional_metadata_to_update = all_existing_metadata.where(state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:optional])

            # only enroll users with no metadata rows (insert), or optional metadata rows (update)
            group_to_insert = group.excluding(all_existing_metadata.pluck(:user_id))
            users_to_insert = User.where(id: group_to_insert)
            users_info_with_optional_2fa_state = users_to_insert.map { |user| { user: user, old_state: :optional } }

            # insert_all ignores duplicates on unique indexes, so safe to run w/ all ids and let AR ignore dupes
            TwoFactorRequirementMetadata
              .insert_all(group_to_insert.map { |id| { user_id: id, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:warning], requirement_reason: requirement_reason.to_value, cohort: cohort, required_by: required_by, original_required_by: required_by } })
            metadata_update_count = optional_metadata_to_update.update_all(state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:warning], requirement_reason: requirement_reason.to_value, cohort: cohort, required_by: required_by, original_required_by: required_by)
            group_update_count += group_to_insert.count + metadata_update_count
            instrument_update_two_factor_requirement_state(users_info: users_info_with_optional_2fa_state)
            update_count += group_update_count
          rescue ActiveRecord::ActiveRecordError => e
            raise ActiveRecord::Rollback
          end
        end

        GitHub.dogstats.distribution("two_factor_requirement.updater.users.count", group_update_count, tags: [
          "requirement_reason:#{requirement_reason}",
          "cohort:#{cohort}",
        ])
      end

      yield(update_count) if block_given?
    end

    def self.set_2fa_requirement_state(user_ids:, new_state:, update_batch_size: 1000)
      raise ArgumentError, "new_state is required" if new_state.nil?

      return if user_ids.nil? || user_ids.empty?
      update_count = 0

      user_ids.in_groups_of(update_batch_size, false) do |group|
        filtered_users = User
          .where(id: group)
          .where("NOT login LIKE ? OR login IN (?)", "%\\_%", User::EnterpriseManagedDependency::INVALID_UNDERSCORE_LOGIN) # exclude EMU users but keep edge case _ users

        batch_update_count = 0

        User.transaction do
          begin
            filtered_metadata = TwoFactorRequirementMetadata.where(user_id: filtered_users.pluck(:id))
            users_info = filtered_metadata.map { |meta| { user: filtered_users.find_by(id: meta.user_id), old_state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES.keys[meta.state] } }
            batch_update_count += filtered_metadata.update_all(state: new_state)

            instrument_update_two_factor_requirement_state(users_info: users_info)
            update_count += batch_update_count
          rescue ActiveRecord::ActiveRecordError => e
            raise ActiveRecord::Rollback
          end
        end

        GitHub.dogstats.distribution("two_factor_requirement.updater.users.count", batch_update_count, tags: [
          "new_state:#{User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES.key(new_state)}",
        ])
      end

      yield(update_count) if block_given?
    end

    def self.instrument_update_two_factor_requirement_state(users_info:)
      return if users_info.nil? || users_info.empty?
      users_info.each do |user_info|
        user = user_info[:user]
        old_state = user_info[:old_state].to_s
        # user object needs to be reloaded to get the new values so the audit log is not referencing the old values
        user.reload.instrument_update_two_factor_requirement_state(old_state: old_state)
      end
    end
    private_class_method :instrument_update_two_factor_requirement_state
  end
end
