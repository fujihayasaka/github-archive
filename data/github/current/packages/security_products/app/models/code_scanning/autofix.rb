# typed: true
# frozen_string_literal: true

module CodeScanning
  class Autofix
    extend T::Sig

    def self.available_in_environment?
      GitHub.code_scanning_enabled? && !GitHub.enterprise?
    end

    def self.enabled_for_repo?(repo)
      repo_settings_configurable?(repo) && CodeScanningRepositoryConfig.new(repo).code_scanning_autofix_settings_enabled?
    end

    def self.enabled_for_org?(org)
      org_settings_configurable?(org) && org.code_scanning_autofix_settings_enabled?
    end

    def self.allowed_by_business?(business)
      policy_available?(business) && business.code_scanning_autofix_policy_allowed?
    end

    def self.code_scanning_autofix_thirdparty_tool?(tool_name)
      ["ESLint"].include?(tool_name)
    end

    def self.generate_for_tool?(repo, tool_name)
      return true if repo.code_scanning_autofix_all_queries_enabled? # Allow all _tools_ and queries to generate autofixes if the (repo-level) FF code_scanning_suggested_all_queries is enabled
      return true if repo.code_scanning_autofix_thirdparty_enabled? && code_scanning_autofix_thirdparty_tool?(tool_name) # Allow thirdparty tool to generate autofixes if the FF code_scanning_suggested_thirdparty is enabled

      tool_name == "CodeQL"
    end

    def self.policy_available?(business)
      return false unless available_in_environment?

      business.advanced_security_purchased?
    end

    def self.repo_settings_configurable?(repository)
      return false unless available_in_environment?

      if repository.code_scanning_autofix_public_repo_enabled?
        return false unless repository.advanced_security_usable?
        return enabled_for_org?(repository.owner) if repository.owner.is_a?(Organization)

        true
      else
        return false unless repository.private? || repository.internal?
        return false unless repository.advanced_security_enabled?

        repository.owner.is_a?(Organization) ? enabled_for_org?(repository.owner) : false
      end
    end

    def self.org_settings_configurable?(organization)
      return false unless available_in_environment?

      if organization.code_scanning_autofix_public_repo_enabled?
        billable_entity = AdvancedSecurityLicense.billable_entity(organization)
        return billable_entity.code_scanning_autofix_policy_allowed? if billable_entity.is_a?(Business)

        true
      else
        billable_entity = AdvancedSecurityLicense.billable_entity(organization)

        case billable_entity
        when Business
          return false unless billable_entity.code_scanning_autofix_policy_allowed?
        when NilClass
          return false
        end

        organization.advanced_security_purchased?
      end
    end

    def self.generate_pr_for_alert(repo, user, alert_number)
      code_scanning_app = Apps::Internal.integration(:code_scanning)
      raise "Code scanning integration not installed!" if code_scanning_app.nil?

      response = GitHub::Turboscan::SuggestedFixes.suggested_fix(
        repository_id: repo.id,
        alert_numbers: [alert_number],
        head_commit_oid: repo.default_branch_ref.target_oid,
        ref_names_bytes: Array(repo.default_branch_ref.qualified_name),
      )

      raise AutofixError.new("Something went wrong") if response&.error.present?

      suggested_fix = response&.data&.suggested_fix_alerts&.[](alert_number)&.suggested_fix

      raise AutofixError.new("No suggested fix found for alert") if suggested_fix.nil? || suggested_fix.dismissed || suggested_fix.outdated

      #
      # At this point we have a suggestion, and we want to create the PR
      #

      # TODO: Add markdown comment in the PR description saying what we are
      # fixing and linking back to the alert using the fancy markdown syntax
      title = "Fix: Alert [#{alert_number}]"
      description = "We are fixing alert number #{alert_number}"

      # Create a new REF
      branch_name = "autofix/alert-#{alert_number}-#{SecureRandom.hex(5)}"
      raise AutofixError.new("Branch name already exists") if repo.heads.find(branch_name)
      # We could add the base commit-oid or a timestamp to make this harder to happen

      ref = repo.heads.create(branch_name, repo.default_branch_ref.target_oid, code_scanning_app.bot)

      diff_entries = suggested_fix.files.each_with_object([]) do |file, out|
        parser = GitHub::Diff::Parser.new(file.diff_content)
        parser.each do |entry|
          out << entry
        end
      end

      # Apply the suggestion to the newly-created ref

      suggested_change = DiffEntrySuggestedChange.new(repository: repo, ref: ref, diff_entries:)
      begin
        suggested_change.commit_change_for_user(
          author: user,
          current_oid: ref.commit.oid,
          message: title, # TODO: Do we want more here?
          sign: true,
          co_author_note: "Co-authored-by: Copilot Autofix powered by AI <#{code_scanning_app.bot.git_author_email}>",
          reflog_data: {
            repo_name: suggested_change.repository.name_with_display_owner,
            repo_public: suggested_change.repository.public?,
            user_login: code_scanning_app.bot.display_login,
            from: GitHub.context[:from],
            via: "code scanning suggested fix",
          }
        )
      end

      # Create the empty PR (no commits yet)
      # We need this before because we are using existing code that applies a suggestion
      # to the PR. If we revisit that code, or reimplement it, we can move this step to
      # after the commits are added.
      pull_request = PullRequest.create_for!(repo, {
        user: user,
        base: repo.default_branch,
        head: ref.name,
        title: title,
        body: description,
      })

      pull_request
    end

    sig { params(repo: Repository, alert_numbers: T::Array[Integer], ref: T.nilable(Git::Ref), head_commit: T.nilable(::Commit)).returns(T::Hash[Integer, Turboscan::Proto::SuggestedFix]) }
    def self.suggested_fixes_for_alerts(repo, alert_numbers, ref: nil, head_commit: nil)
      return {} if alert_numbers.empty?

      ref ||= repo.default_branch_ref
      head_commit ||= ref.commit

      suggested_fixes_response = GitHub::Turboscan::SuggestedFixes.suggested_fix(
        repository_id: repo.id,
        alert_numbers: alert_numbers,
        head_commit_oid: head_commit.oid,
        ref_names_bytes: [ref.qualified_name.b],
      )

      # If there is missing data we just return the empty response
      unless suggested_fixes_response.present? && suggested_fixes_response.data.present?
        return {}
      end

      T.must(T.must(suggested_fixes_response).data).suggested_fix_alerts.each_with_object({}) do |(number, sfa), out|
        suggested_fix = sfa.suggested_fix
        unless suggested_fix.nil? || suggested_fix.dismissed || suggested_fix.outdated
          out[number] = suggested_fix
        end
      end
    end

    def self.can_dismiss_code_scanning_suggested_fix?(repo, user)
      repo.pushable_by?(user)
    end
  end
end
