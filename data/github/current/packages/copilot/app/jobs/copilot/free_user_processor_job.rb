# typed: strict
# frozen_string_literal: true

module Copilot
  class FreeUserProcessorJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    extend T::Sig

    locked_by timeout: 20.minutes, key: DEFAULT_LOCK_PROC
    gate_with_feature_flag :copilot_free_user_check_job

    # this job can take any free user in - whether it needs updating or not and handle it.
    # only subscribed free users can be checked for their qualification
    # if the user is not subscribed and gets passed to this job, we delete the record
    sig { params(copilot_free_user_id: Integer).void }
    def perform(copilot_free_user_id)
      GitHub.logger.with_named_tags("code.function" => "perform", "gh.copilot.free_user.id" => copilot_free_user_id) do
        free_user = Copilot::FreeUser.find_by(id: copilot_free_user_id)

        # this seems like it shouldn't happen, but this is sparta
        unless free_user
          GitHub.dogstats.increment("copilot.free_user_processor_job.free_user_not_found")
          GitHub.logger.info("Free user not found")
          return
        end

        GitHub.logger.info("Processing user")

        # If a user has a CFB seat, we don't want to refresh or cancel their CFI access.
        if has_seat?(free_user)
          GitHub.logger.info("This user already has a CFB seat")
          return
        end

        process_free_user(free_user)
      end
    end

    sig { params(free_user: Copilot::FreeUser).void }
    def process_free_user(free_user)
      named_tags = {
        "code.function" => "process_free_user",
        "gh.copilot.free_user.free_user_type" => free_user.free_user_type,
        "gh.copilot.free_user.user_id" => free_user.user_id,
        "gh.copilot.free_user.next_check_at" => free_user.next_check_at
      }
      GitHub.logger.with_named_tags(named_tags) do
        # Let's just make sure that we're not going to have a nil user
        if free_user.user.nil?
          GitHub.dogstats.increment("copilot.free_user_processor_job.user_nil")
          GitHub.logger.info("Free user has a nil user, deleting record")
          with_write do
            free_user.destroy
          end
          return
        end

        # if the user is not subscribed, we delete the record
        # we're cool with this because the user can always be recreated
        unless free_user.subscribed?
          GitHub.dogstats.increment("copilot.free_user_processor_job.free_user_not_subscribed")
          GitHub.logger.info("Free user not subscribed, deleting record")
          with_write do
            free_user.destroy
          end
          return
        end

        user = T.must(free_user.user)
        copilot_user = Copilot::User.new(user)

        case free_user.type
        when Copilot::FreeUser::COMPLIMENTARY_ACCESS
          GitHub.dogstats.increment("copilot.free_user_processor_job.complimentary_access")

          # This is a happy thing - they got free access for a while - hope they liked it!
          if free_user.should_update?
            GitHub.dogstats.increment("copilot.free_user_processor_job.complimentary_access.limited")
            GitHub.logger.info("Complimentary access user in the past, warning and queueing cancel")

            with_write do
              free_user.warn_and_queue_cancel!
            end
          else
            GitHub.dogstats.increment("copilot.free_user_processor_job.complimentary_access.infinite")
            ###### 🚨🚨🚨🚨🚨🚨🚨🚨🐿🚨🐿🚨🐿🚨🐿🚨🚨🚨🚨🚨🚨🚨 ######
            # This should never happen.  We need to tell someone important about this.
            # Like a 🦈
            ###### 🚨🚨🚨🚨🚨🚨🚨🚨🐿🚨🐿🚨🐿🚨🐿🚨🚨🚨🚨🚨🚨🚨 ######
            tell_someone_about_it(free_user)

            error = StandardError.new("Future Complimentary Users Cannot Be Updated")
            error_payload = named_tags.merge({ exception: error })
            GitHub.logger.error("Future Complimentary Users Cannot Be Updated", error_payload)

            Failbot.report(error, free_user: free_user)
          end
        # For educational users, we need to check if they still have a coupon
        when Copilot::FreeUser::EDUCATIONAL
          GitHub.dogstats.increment("copilot.free_user_processor_job.educational")

          if Copilot::FreeUser.is_educational_user?(copilot_user)
            # this user still has a coupon, so we refresh the user's access
            GitHub.logger.info("Educational user still has a coupon, refreshing")

            with_write do
              free_user.refresh!
            end
          else
            # no coupon left, we cancel this user
            GitHub.logger.info("Educational user no longer has a coupon, warning and queueing cancel")

            with_write do
              free_user.warn_and_queue_cancel!
            end
          end
        # For engaged oss users, we need to check if they still have a repo
        when Copilot::FreeUser::ENGAGED_OSS
          GitHub.dogstats.increment("copilot.free_user_processor_job.engaged_oss")

          if Copilot::FreeUser.is_engaged_oss_user?(copilot_user)
            # this user still has engaged oss access, so we refresh the user's access
            GitHub.logger.info("Engaged OSS user still has a repo, refreshing")

            with_write do
              free_user.refresh!
            end
          else
            # no engaged oss access, we cancel this user
            GitHub.logger.info("Engaged OSS user no longer has a repo, warning and queueing cancel")

            with_write do
              free_user.warn_and_queue_cancel!
            end
          end

        # For faculty users, we need to check if they still have a coupon
        when Copilot::FreeUser::FACULTY
          GitHub.dogstats.increment("copilot.free_user_processor_job.faculty")

          if Copilot::FreeUser.is_faculty_user?(copilot_user)
            # this user still has a coupon, so we refresh the user's access
            GitHub.logger.info("Faculty user still has a coupon, refreshing")

            with_write do
              free_user.refresh!
            end
          else
            # no coupon left, we cancel this user
            GitHub.logger.info("Faculty user no longer has a coupon, warning and queueing cancel")

            with_write do
              free_user.warn_and_queue_cancel!
            end
          end
        # For github star users, we need to make sure they are still part of the stars team
        when Copilot::FreeUser::GITHUB_STAR
          GitHub.dogstats.increment("copilot.free_user_processor_job.github_star")

          if Copilot::FreeUser.is_github_star_user?(copilot_user)
            # this user still has org/team access, so we refresh the user's access
            GitHub.logger.info("Github star user still has access, refreshing")

            with_write do
              free_user.refresh!
            end
          else
            # no org/team access, we cancel this user
            GitHub.logger.info("Github star user no longer has access, warning and queueing cancel")

            with_write do
              free_user.warn_and_queue_cancel!
            end
          end
        # for ms mvps, we need to make sure they still have the coupon
        when Copilot::FreeUser::MS_MVP
          GitHub.dogstats.increment("copilot.free_user_processor_job.ms_mvp")

          if Copilot::FreeUser.is_ms_mvp_user?(copilot_user)
            # this user still has a coupon, so we refresh the user's access
            GitHub.logger.info("MS MVP user still has a coupon, refreshing")

            with_write do
              free_user.refresh!
            end
          else
            # no coupon left, we cancel this user
            GitHub.logger.info("MS MVP user no longer has a coupon, warning and queueing cancel")

            with_write do
              free_user.warn_and_queue_cancel!
            end
          end
        # For technical preview extensions, if we reach this time, their 60 days are up
        when Copilot::FreeUser::TECHNICAL_PREVIEW_EXTENSION
          GitHub.dogstats.increment("copilot.free_user_processor_job.technical_preview_extension")

          GitHub.logger.info("Technical preview extension user's 60 days are up, warning and queueing cancel")
          with_write do
            free_user.warn_and_queue_cancel!
          end
        # for workshop users, we need to make sure they still have the coupon
        when Copilot::FreeUser::WORKSHOP
          GitHub.dogstats.increment("copilot.free_user_processor_job.workshop")

          if Copilot::FreeUser.is_workshop_user?(copilot_user)
            # this user still has a coupon, so we refresh the user's access
            GitHub.logger.info("Workshop user still has a coupon, refreshing")

            with_write do
              free_user.refresh!
            end
          else
            # no coupon left, we cancel this user
            GitHub.logger.info("MS MVP user no longer has a coupon, warning and queueing cancel")

            with_write do
              free_user.warn_and_queue_cancel!
            end
          end
        # For Y Combinator users, if we reach this time, their 1 year is up
        when Copilot::FreeUser::Y_COMBINATOR
          GitHub.dogstats.increment("copilot.free_user_processor_job.y_combinator")

          GitHub.logger.info("Y Combinator user's 1 year is up, warning and queueing cancel")
          with_write do
            free_user.warn_and_queue_cancel!
          end
        else
          GitHub.dogstats.increment("copilot.free_user_processor_job.other")
          ###### 🚨🚨🚨🚨🚨🚨🚨🚨🐿🚨🐿🚨🐿🚨🐿🚨🚨🚨🚨🚨🚨🚨 ######
          # This should never happen.  We need to tell someone important about this.
          # Like a 🦈
          ###### 🚨🚨🚨🚨🚨🚨🚨🚨🐿🚨🐿🚨🐿🚨🐿🚨🚨🚨🚨🚨🚨🚨 ######
          tell_someone_about_it(free_user)

          error = StandardError.new("Unknown Users Cannot Be Updated")
          error_payload = named_tags.merge({ exception: error })
          GitHub.logger.error("Users Cannot Be Updated", error_payload)
          Failbot.report(error, free_user: free_user)
          nil
        end
      end
    end

    sig { params(free_user: Copilot::FreeUser).void }
    def tell_someone_about_it(free_user)
      msg = "🐿🚨🦈 *FreeUserProcessorJob Error* 🐿🚨🦈 _Non-updateable free user attempted to be updated_ #{free_user}"
      chatterbox_say(msg)
    end

    sig { params(free_user: Copilot::FreeUser).returns(T::Boolean) }
    def has_seat?(free_user)
      Copilot::Seat.exists?(assigned_user_id: free_user.user_id)
    end
  end
end
