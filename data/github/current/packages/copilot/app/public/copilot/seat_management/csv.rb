# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class Csv

      GitHubUser = T.type_alias do
        {
          new_user: T::Boolean,
          user: ::User,
          source_type: Symbol,
          source_email: T.nilable(String)
        }
      end

      sig do
        params(
          organization: ::Organization,
          uploaded_csv: ActionDispatch::Http::UploadedFile
        ).returns(GitHub::Result)
      end
      def self.parse(organization, uploaded_csv)
        GitHub::Result.new do
          records = process_csv(uploaded_csv)
          raise StandardError, "No valid users found" if records.empty?

          found_errors, emails, logins = extract_csv_records(records)

          # get all the users by their email
          # note: this business property is just here to add the emu shortcode, and doesnt scope to "this business"
          # the keys have the emu shortcode removed
          users_by_email = ::User.find_by_emails(emails, business: organization.business)
          users_by_login = ::User.where(login: logins).to_a

          email_user_map = users_by_email.inject({}) do |memo, (email, user)|
            memo[user.id] = email.downcase
            memo
          end

          # all the users we know about from their email, emu aware
          known_users_from_emails = users_by_email.values

          # all the emails and logins that cannot be mapped to users on GitHub
          missing_user_emails = emails - users_by_email.keys
          missing_user_logins = logins - users_by_login.map(&:display_login).map(&:downcase)

          # a trap for if there exist users with both their email and login in the csv
          all_found_users = (known_users_from_emails + users_by_login).uniq(&:id)

          org_user_ids = T.let(organization.people_ids, T::Array[Integer])

          found_errors = (found_errors + missing_user_logins).flatten

          github_users = []
          private_email_users = []

          all_found_users.each do |user|
            is_org_member = org_user_ids.include?(user.id)
            found_by_email = email_user_map.key?(user.id)
            # This is the email supplied by the CSV, used to find the user
            source_email = user.add_emu_shortcode_to_emails(email_user_map[user.id], business: organization.business)
            # This is our best guess at the public email we can return for the user
            user_email = source_email.nil? ? user.primary_user_email : user.emails.find_by(email: source_email)
            # EMU users emails will always be "public" in the sense that the org or business will
            # always know their email address due to provisioning.
            email_is_public = user_email&.public? || user.is_enterprise_managed?

            # Determine if this user should be a github_user or an email_user
            if found_by_email && (!is_org_member || !email_is_public)
              # Users found by email who either:
              # - aren't org members
              # - are org members but have private emails
              # - are not org members and have public emails
              # Should be treated as email users
              private_email_users << source_email
            else
              # All other users are treated as github users. This could be:
              #   - Users found by login
              #   - Users found by email who are org members and have public emails
              #   - Users found by email who are org members but have private emails
              github_users << {
                new_user: !is_org_member,
                user: user,
                source_type: found_by_email ? :email : :login,
                source_email: email_is_public ? user_email&.email : nil
              }
            end
          end

          # Add private email users to the missing emails list
          all_email_users = missing_user_emails + private_email_users

          # Calculate new_users_count. We want to treat users with private emails as new users
          # to further protect their privacy and to avoid leaking information about whether they
          # have GitHub accounts or not.
          new_users_count = (all_email_users.count + github_users.count { |u| u[:new_user] })

          {
            new_users: new_users_count,
            github_users: github_users,
            email_users: all_email_users,
            found_errors: found_errors,
            total_users: missing_user_emails.count + all_found_users.count
          }
        end
      end

      sig do
        params(organization: ::Organization, uploaded_csv: ActionDispatch::Http::UploadedFile)
          .returns({
            found_errors: T.nilable(T::Array[String]),
            new_users: T.nilable(Integer),
            email_users: T.nilable(T::Array[String]),
            github_users: T::Array[{ new_user: T::Boolean, user: ::User }],
            total_users: T.nilable(Integer)
          })
      end
      def self.parse_as_json(organization, uploaded_csv)
        result = Copilot::SeatManagement::Csv.parse(organization, uploaded_csv)

        return {
          found_errors: [],
          new_users: 0,
          email_users: [],
          github_users: [],
          total_users: 0
        } unless result.ok?

        hash = result.value!

        users = hash[:github_users].nil? ? [] : hash[:github_users]

        {
          found_errors: hash[:found_errors],
          new_users: hash[:new_users],
          email_users: hash[:email_users],
          github_users: users.map { |user| Copilot::SeatManagement::Csv.serialize_user(T.cast(user, GitHubUser)) },
          total_users: hash[:total_users]
        }
      end

      sig do
        params(data: GitHubUser)
          .returns(T::Hash[String, T.any(String, T::Boolean)])
      end
      def self.serialize_user(data)
        user = data[:user]

        {
          id: user.id,
          email: user.remove_shortcode(data[:source_email]),
          display_login: user.display_login,
          profile_name: user.profile_name,
          avatar: user.primary_avatar_url(50),
          is_new_user: data[:new_user],
          email_input_csv: data[:source_type] == :email,
        }
      end

      sig do
        params(copilot_organization: Copilot::Organization,
               github_usernames: T::Array[::String],
               email_users: T::Array[String],
               current_user: ::User).void
      end
      def self.save(copilot_organization, github_usernames, email_users, current_user)
        if github_usernames.any?
          github_users = ::User.where(login: github_usernames).to_a
          copilot_organization.assign(github_users, current_user)
        end

        if email_users.any?
          copilot_organization.assign(email_users, current_user)
        end
      end

      sig do
        params(uploaded_csv: ActionDispatch::Http::UploadedFile)
          .returns(T::Array[String])
      end
      def self.process_csv(uploaded_csv)
        GitHub.logger.with_named_tags("code.function" => "process_csv") do
          rows = CSV.parse(uploaded_csv.read)
          rows.flat_map do |row|
            row.map { |item| item.to_s.gsub(/\r|\n|,|\ /, "").to_s.strip }
          end
        end
      rescue CSV::MalformedCSVError => e
        GitHub.logger.error("There was an error parsing CSV file", e)
        GitHub.logger.info("Trying to manually parse the CSV because YOLO")
        uploaded_csv.rewind # BE KIND, REWIND
        uploaded_csv.read.split(",").map do |row|
          row.gsub(/\r|\n/, "").to_s.strip
        end
      end

      sig { params(csv_data: T::Array[String]).returns([T::Array[String], T::Array[String], T::Array[String]]) }
      def self.extract_csv_records(csv_data)
        found_errors = []
        emails = []
        logins = []

        csv_data.compact.uniq.each do |csv_user|
          next unless csv_user.present?

          if csv_user.include?("@")
            if ::User.valid_email?(csv_user)
              emails << csv_user.downcase
            else
              found_errors << csv_user
            end
          else
            logins << csv_user.downcase
          end
        end

        [found_errors, emails, logins]
      end
    end
  end
end
