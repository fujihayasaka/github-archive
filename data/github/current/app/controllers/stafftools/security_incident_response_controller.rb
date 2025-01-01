# typed: true
# frozen_string_literal: true

require "csv"

module Stafftools
  class SecurityIncidentResponseController < StafftoolsController
    BATCH_SIZE = 1000

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Copilot,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      only: [:index]

    def index
      return render_404 unless current_user.security_incident_response_access?
      render "stafftools/security_incident_response/index"
    end

    def create
      return render_404 unless current_user.security_incident_response_access?

      # Ensure a valid incident reference number is passed
      if params[:reference_number].blank?
        flash[:error] = "No reference number specified!"
        return redirect_to stafftools_security_incident_response_path
      end

      # Validate dry run options and that the dry run user exists
      if params[:dry_run].to_i == 1
        user_id = params[:dry_run_user_id]
        if user_id.blank?
          flash[:error] = "A dry run was selected but no user ID was specified!"
          return redirect_to stafftools_security_incident_response_path
        end

        if user_id.to_i.to_s != user_id
          flash[:error] = "A dry run was selected but the User ID was invalid!"
          return redirect_to stafftools_security_incident_response_path
        end

        if ::User.find_by(id: user_id).nil?
          flash[:error] = "A dry run was selected but the User with ID #{user_id} could not be found!"
          return redirect_to stafftools_security_incident_response_path
        end
      end

      # Ensure that a CSV of user data is passed
      users_csv = params[:users]
      if users_csv.blank?
        flash[:error] = "No users CSV specified!"
        return redirect_to stafftools_security_incident_response_path
      end

      # Some variables which will be global to each background job
      users = []
      email_template_data = ""
      would_have_revoked_tokens = T.let(false, T::Boolean)
      recommendations_to_revoke = T.let([], T::Array[T.untyped])
      stars_to_revoke = T.let([], T::Array[T.untyped])
      oauth_authorizations_to_revoke = T.let([], T::Array[T.untyped])
      oauth_tokens_to_revoke = T.let([], T::Array[T.untyped])
      fine_grained_tokens_to_revoke = T.let([], T::Array[T.untyped])

      # # Make sure the file pointer is at the beginning of the file
      users_csv.rewind

      # # Read the entire file content
      users_csv_data = users_csv.read.force_encoding("UTF-8")

      # Normalize the line endings
      users_csv_data.gsub!(/\r\n?/, "\n")

      # Remove BOM if it exists
      bom = "\xEF\xBB\xBF"
      users_csv_data.gsub!(/\A#{bom}/, "")

      # Parse the CSV
      # Note: We also pull out any IDs which will need to be revoked
      # e.g. oauth tokens, oauth authorizations, etc...
      begin
        T.must(CSV.parse(users_csv_data, liberal_parsing: true, headers: true)).each_with_index do |users_csv_row, index|
          row_number = index + 2
          row = T.cast(users_csv_row, CSV::Row)
          if row["user_id"].nil?
            flash[:error] = "Users CSV malformed, it appears row #{row_number} is missing a user_id"
            return redirect_to stafftools_security_incident_response_path
          end

          user_id = if params[:dry_run].to_i == 1
            params[:dry_run_user_id].to_i
          else
            row["user_id"].to_i
          end

          if row["recommendations_to_revoke"].present?
            recommendations = row["recommendations_to_revoke"].split(",").map do |id|
              if id.to_i.to_s != id
                flash[:error] = "Recommendations to revoke can only take a list of comma seperated IDs!"
                return redirect_to stafftools_security_incident_response_path
              end
              id.to_i
            end

            recommendations_to_revoke = recommendations_to_revoke | recommendations
          end

          if row["stars_to_revoke"].present?
            stars = row["stars_to_revoke"].split(",").map do |id|
              if id.to_i.to_s != id
                flash[:error] = "Stars to revoke can only take a list of comma seperated IDs!"
                return redirect_to stafftools_security_incident_response_path
              end
              id.to_i
            end

            stars_to_revoke = stars_to_revoke | stars
          end

          if row["oauth_authorizations_to_revoke"].present?
            authorizations = row["oauth_authorizations_to_revoke"].split(",").map do |id|
              if id.to_i.to_s != id
                flash[:error] = "Oauth Authorizations to revoke can only take a list of comma seperated IDs!"
                return redirect_to stafftools_security_incident_response_path
              end
              id.to_i
            end

            oauth_authorizations_to_revoke = oauth_authorizations_to_revoke | authorizations
          end

          if row["oauth_tokens_to_revoke"].present?
            tokens = row["oauth_tokens_to_revoke"].split(",").map do |id|
              if id.to_i.to_s != id
                flash[:error] = "Oauth Tokens to revoke can only take a list of comma seperated IDs!"
                return redirect_to stafftools_security_incident_response_path
              end
              id.to_i
            end

            oauth_tokens_to_revoke = oauth_tokens_to_revoke | tokens
          end

          if row["fine_grained_tokens_to_revoke"].present?
            tokens = row["fine_grained_tokens_to_revoke"].split(",").map do |id|
              if id.to_i.to_s != id
                flash[:error] = "Fine grained tokens to revoke can only take a list of comma separated IDs!"
                return redirect_to stafftools_security_incident_response_path
              end
              id.to_i
            end

            fine_grained_tokens_to_revoke = fine_grained_tokens_to_revoke | tokens
          end

          data = []

          row.headers.each_with_index do |header, index|
            # Ignore special cases
            if header == "user_id" ||
              header == "recommendations_to_revoke" ||
              header == "stars_to_revoke" ||
              header == "oauth_authorizations_to_revoke" ||
              header == "oauth_tokens_to_revoke" ||
              header == "fine_grained_tokens_to_revoke"
              next
            end

            if header.nil?
              flash[:error] = "Users CSV malformed, it appears that row #{row_number} contains extra data"
              return redirect_to stafftools_security_incident_response_path
            end

            value = row.fields[index]

            if value.nil?
              flash[:error] = "Users CSV malformed, it appears that row #{row_number} is missing data"
              return redirect_to stafftools_security_incident_response_path
            end

            data.append({
              key: header,
              value: value
            })
          end

          # We still want to parse the entire CSV to validate the format
          # but in the dry run we should not process more than the first user
          next if params[:dry_run].to_i == 1 && users.length == 1

          users.append({
            id: user_id,
            data: data
          })
        end

        # Parsing the user CSV lead to no users
        if users.blank?
          flash[:error] = "Parsing of users CSV failed, please double check the format."
          return redirect_to stafftools_security_incident_response_path
        end

        # A valid user CSV was provided but no options were selected
        # and the special headers used to revoke tokens were not present
        # in the CSV so fail fast indicating that no action will be performed
        if params[:perform_notify].to_i == 0 &&
           params[:reset_passwords].to_i == 0 &&
            params[:suspend].blank? &&
            params[:staffnote].blank? &&
            recommendations_to_revoke.empty? &&
            stars_to_revoke.empty? &&
            oauth_tokens_to_revoke.empty? &&
            oauth_authorizations_to_revoke.empty? &&
            fine_grained_tokens_to_revoke.empty?

          flash[:error] = "No option selected! No job has been queued"
          return redirect_to stafftools_security_incident_response_path
        end

        if params[:perform_notify].to_i == 1
          if params[:notify_from].blank?
            flash[:error] = "Notify was selected but no email address was provided!"
            return redirect_to stafftools_security_incident_response_path
          end

          if params[:notify_subject].blank?
            flash[:error] = "Notify was selected but no subject was provided!"
            return redirect_to stafftools_security_incident_response_path
          end

          if params[:notify_template].blank?
            flash[:error] = "Notify was selected but no template was provided!"
            return redirect_to stafftools_security_incident_response_path
          end

          email_template_data = params[:notify_template].read

          if email_template_data.blank?
            flash[:error] = "Notify was selected but the provided template was blank!"
            return redirect_to stafftools_security_incident_response_path
          end
        end

        users.in_groups_of(BATCH_SIZE, false) do |user_group|
          incident_response_user_actions = {
            users: user_group,
          }

          if params[:reset_passwords].to_i == 1
            incident_response_user_actions[:reset_password] = true
          end

          if !params[:suspend].blank?
            incident_response_user_actions[:suspend] = params[:suspend]
          end

          if !params[:staffnote].blank?
            incident_response_user_actions[:staffnote] = params[:staffnote]
          end

          if params[:perform_notify].to_i == 1
            incident_response_user_actions[:notify] = {
              from: params[:notify_from],
              subject: params[:notify_subject],
              template: email_template_data
            }
          end

          # We only want to revoke tokens if we're not in a dry run
          if params[:dry_run].to_i == 0
            if !recommendations_to_revoke.empty?
              incident_response_user_actions[:remove_repository_recommendations] = recommendations_to_revoke
            end

            if !stars_to_revoke.empty?
              incident_response_user_actions[:remove_repository_stars] = stars_to_revoke
            end

            if !oauth_authorizations_to_revoke.empty?
              incident_response_user_actions[:revoke_oauth_authorizations] = oauth_authorizations_to_revoke
            end

            if !oauth_tokens_to_revoke.empty?
              incident_response_user_actions[:revoke_oauth_tokens] = oauth_tokens_to_revoke
            end

            if !fine_grained_tokens_to_revoke.empty?
              incident_response_user_actions[:revoke_fine_grained_tokens] = fine_grained_tokens_to_revoke
            end
          elsif !recommendations_to_revoke.empty? ||
            !stars_to_revoke.empty? ||
            !oauth_authorizations_to_revoke.empty? ||
            !oauth_tokens_to_revoke.empty? ||
            !fine_grained_tokens_to_revoke.empty?
            would_have_revoked_tokens = true
          end

          # Prevent queueing a job in this case
          # as the dry run will perform no action
          if params[:perform_notify].to_i == 0 &&
           params[:reset_passwords].to_i == 0 &&
            params[:suspend].blank? &&
            params[:staffnote].blank? &&
            would_have_revoked_tokens
            next
          end

          SecurityIncidentResponseJob.perform_later(
            actor: current_user,
            id: params[:reference_number],
            incident_responses: [
              incident_response_user_actions
            ]
          )
        end
      rescue CSV::MalformedCSVError => e
        flash[:error] = "Parsing of users CSV failed: " + e.message
        return redirect_to stafftools_security_incident_response_path
      end

      if params[:dry_run].to_i == 1
        if would_have_revoked_tokens
          flash[:notice] = "Dry run of incident response job queued for #{params[:reference_number]}! Items would have been revoked if this was not a dry run."
        else
          flash[:notice] = "Dry run of incident response job queued for #{params[:reference_number]}!"
        end
      else
        flash[:notice] = "Incident response job queued for #{params[:reference_number]}!"
      end

      redirect_to stafftools_security_incident_response_path
    end
  end
end
