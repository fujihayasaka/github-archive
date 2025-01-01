# typed: true
# frozen_string_literal: true
module Stafftools
  class BulkTicketersView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    # Returns [ticket_data, rejected, failed_lines]
    #  ticket_data: array of hashes of repo/user and contact ticket data for urls
    #  rejected: array of repository/user nwo that couldn't be processed
    #
    # consumed by https://github.com/github/zendesk-gh-sidecar
    def ticket_data_for_urls(urls)
      grouped, failed_lines = GitHub::Stafftools.group_urls_by_nwo_or_user(urls)
      rejected = []

      ticket_data = grouped.map do |nwo, urlhits|
        is_repo = nwo.include?("/")
        if is_repo
          repo = GitHub::Stafftools.repo_from_nwo(nwo)
          repo_url = repo&.http_url&.chomp(".git")
          contact_ids, contacts = contacts_for_owner(repo&.owner).yield_self { |h| [h.keys, h.values] }
          if repo && repo_url && contacts&.any?
            {
              "contacts": contacts,
              "contact_ids": contact_ids,
              "data": {
                "name": repo.owner.safe_profile_name,
                "login": repo.owner.login,
                "repo": repo_url,
                "urlhits": urlhits,
              },
             }
          else
            rejected.push(nwo)
            nil
          end
        else
          user = ::User.with_logins(nwo).first
          user_url = "#{GitHub.url}/#{user.login}"
          contact_ids, contacts = contacts_for_owner(user).yield_self { |h| [h.keys, h.values] }
          if user && user_url && contacts&.any?
            {
              "contacts": contacts,
              "contact_ids": contact_ids,
              "data": {
                "name": user.safe_profile_name,
                "login": user.display_login,
                "repo": user_url,
                "urlhits": urlhits,
              },
            }
          else
            rejected.push(nwo)
            nil
          end
        end
      end

      [ticket_data.compact, rejected, failed_lines]
    end

    def dmca_template
      <<~HEREDOC
        Hi {{name}},

        I'm contacting you on behalf of GitHub because we've received a DMCA takedown notice regarding the following content:

        {{#urlhits}}
          {{.}}
        {{/urlhits}}

        We're giving you 1 business day to make the changes identified in the following notice:



        If you need to remove specific content from your repository, simply making the repository private or deleting it via a commit won't resolve the alleged infringement. Instead, you must follow these instructions to remove the content from your repository's history, even if you don't think it's sensitive:

        #{GitHub.help_url}/articles/remove-sensitive-data

        Once you've made changes, please reply to this message and let us know. If you don't tell us that you've made changes within the next 1 business day, we'll need to disable the entire repository according to our GitHub DMCA Takedown Policy:

        #{GitHub.help_url}/articles/dmca-takedown-policy/

        If you believe your content on GitHub was mistakenly disabled by a DMCA takedown request, you have the right to contest the takedown by submitting a counter notice, as described in our DMCA Takedown Policy.

        PLEASE NOTE: It is important that you reply to this message within 1 business day to tell us whether you've made changes. If you do not, the repository will be disabled.
      HEREDOC
    end

    private

    # returns hash mapping ID to contact email
    def contacts_for_owner(owner)
      return {} unless owner
      contacts = {}
      if owner.organization?
        owner.contactable_admins.each do |u|
          contacts[u.id] = u.email_for_contact if u.email_for_contact.present?
        end
      else
        contacts[owner.id] = owner.email_for_contact if owner.email_for_contact.present?
      end
      contacts
    end
  end
end
