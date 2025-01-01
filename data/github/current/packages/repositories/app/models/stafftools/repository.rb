# typed: true
# frozen_string_literal: true

module Stafftools
  class Repository < SimpleDelegator
    def self.for_team(team, page = 1)
      repos = team.repositories_scope.order(:name).preload(
        :owner,
        :mirror,
        network: :root,
        parent: :owner,
      ).paginate(page: page)

      roles = repos.each_with_object({}) do |repo, roles_hash|
        roles_hash[repo.id] = team.async_most_capable_action_or_role_for(repo, include_custom_roles: true, role_priority: true)
      end
      abilities = team.most_capable_abilities_on_subjects(repos.pluck(:id), subject_type: ::Repository)
      teams = ::Team.where(id: abilities.values.map(&:actor_id)).index_by(&:id)

      Promise.all(roles.values).sync

      mapped_repos = repos.map do |repo|
        ability = abilities[repo.id]
        role = roles[repo.id].value
        is_inherited = ability.actor_id != team.id
        origin_name = teams[ability.actor_id].name
        new(repo, ability, role, is_inherited, origin_name)
      end

      Stafftools::PaginatedCollection.create(repos, mapped_repos)
    end

    attr_reader :ability, :role, :is_inherited, :ability_origin

    def initialize(repo, ability, role, is_inherited, origin_name)
      @ability = ability
      @role = role
      @is_inherited = is_inherited
      @ability_origin = origin_name
      super repo
    end

    DISABLE_TEMPLATE_FOR_SIZE_ENTERPRISE = <<~MUSTACHE.chomp
      Access to the {{repository_name_with_owner}} repository has been disabled due to excessive use of resources.

      Please contact your site administrator to restore access.

      {{instructions}}
    MUSTACHE

    DISABLE_TEMPLATE_FOR_SIZE_DOT_COM = <<~MUSTACHE.chomp
      <p>
        Access to the {{repository_name_with_owner}} repository has been disabled due to excessive use of resources.
      </p>

      <p>
        This action was taken after determining that the reported content violates our Acceptable Use Policy by using excessive bandwidth or otherwise placing undue burden on our infrastructure. Read more about GitHub's Acceptable Use Policies here: {{{github_help_url}}}.
      </p>

      <p>
        When making content moderation decisions, we consider information from a variety of sources, including: account profile data, information contained in submitted reports/notices or discovered through our own voluntarily initiated investigations, and context around the contents of the repository.
      </p>

      <p>
        If you wish to regain access to the disabled content or would like to dispute that a violation occurred and can provide additional information to show that a different decision should have been reached, please review our {{{github_appeal_reinstatement_docs_url}}} and submit a request via our {{{reinstatement_request_form_url}}}.
      </p>

      <p>
        Please feel free to {{{contact_support_url}}} if you have any questions.
      </p>

      <p>
        {{instructions}}
      </p>

      <p>
        Thanks,
      </p>

      <p>
        GitHub Trust & Safety
      </p>
    MUSTACHE

    DISABLE_TEMPLATE_FOR_TOS = <<~MUSTACHE.chomp
      <p>
        Access to the {{repository_name_with_owner}} repository has been disabled by GitHub staff due to a terms of service violation.
      </p>

      <p>
        When making content moderation decisions, we consider information from a variety of sources, including: account profile data, information contained in submitted reports/notices or discovered through our own voluntarily initiated investigations, and context around the contents of the repository.
      </p>

      <p>
        If you wish to regain access to the disabled content or would like to dispute that a violation occurred and can provide additional information to show that a different decision should have been reached, please review our {{{github_appeal_reinstatement_docs_url}}} and submit a request via our {{{reinstatement_request_form_url}}}.
      </p>

      <p>You may review our terms of service here: {{{github_help_url}}}</p>

      <p>
        Please feel free to {{{tos_violation_review_link}}} if you have any questions.
      </p>

      <p>{{instructions}}</p>
    MUSTACHE

    DISABLE_TEMPLATE_FOR_TRADEMARK = <<~MUSTACHE.chomp
      <p>
        Access to the {{repository_name_with_owner}} repository has been disabled by GitHub Staff as a result of a violation of GitHub's Trademark Policy.
      </p>

      <p>
        This action was taken after determining that the reported content violates our Acceptable Use Policy prohibiting infringement of proprietary rights. We do not allow content or activity that infringes any proprietary right of any party, including patent, trademark, trade secret, copyright, right of publicity, or other right. Read more about GitHub's Trademark Policy here: {{{github_help_url}}}
      </p>

      <p>
        When making content moderation decisions, we consider information from a variety of sources, including: account profile data, information contained in submitted reports/notices or discovered through our own voluntarily initiated investigations, and context around the contents of the repository.
      </p>

      <p>
        If you wish to regain access to the disabled content or would like to dispute that a violation occurred and can provide additional information to show that a different decision should have been reached, please review our {{{github_appeal_reinstatement_docs_url}}} and submit a request via our {{{contact_url}}}.
      </p>

      <p>
        Please feel free to {{{contact_support_url}}} if you have any questions.
      </p>

      <p> {{instructions}} </p>

      <p>Thanks,</p>
      <p>GitHub Trust & Safety</p>
    MUSTACHE

    DISABLE_TEMPLATE_FOR_PRIVATE_INFORMATION = <<~MUSTACHE.chomp
      <p>
        Access to the {{repository_name_with_owner}} repository has been disabled by GitHub Staff as a result of a private information removal request.
      </p>

      <p>
        This action was taken after determining that the reported content violates our Acceptable Use Policy prohibiting posting of proprietary and/or private information. We do not allow content or activity on GitHub that infringes any proprietary right of any party or violates the privacy of any third party. Read more about GitHub's Private Information Removal Policy here: {{{github_help_url}}}
      </p>

      <p>
        When making content moderation decisions, we consider information from a variety of sources, including: account profile data, information contained in submitted reports/notices or discovered through our own voluntarily initiated investigations, and context around the contents of the repository.
      </p>

      <p>
        If you wish to regain access to the disabled content or would like to dispute that a violation occurred and can provide additional information to show that a different decision should have been reached, please review our {{{github_appeal_reinstatement_docs_url}}} and submit a request via our {{{contact_url}}}.
      </p>

      <p> {{instructions}} </p>

      <p>Thanks,</p>
      <p>GitHub Trust & Safety</p>
    MUSTACHE

    TEMPLATE_FOR_BANNER_CONTENT_WARNING = <<~MUSTACHE.chomp
      <p>
        A content notification banner bas been added to the {{repository_name_with_owner}} repository due to concerns from our
        community that the contents of the repository may include the following:
      </p>

      <p>{{content_warning_reason}}</p>

      {{#is_student_pages}}
      <p>
        This action was taken after determining that the reported content could cause trademark confusion with a company or brand, which would be a violation of our Acceptable Use Policy prohibiting content that infringes on any proprietary right of any party, including patent, trademark, trade secret, copyright, right of publicity, or other right.
      </p>

      <p>
        In order to decrease the likelihood of confusion, a dismissible banner has been added to the repository containing the following notification:
      </p>

      <p>---</p>

      <p>This page was made as a personal project in connection with an educational exercise.</p>

      <p>
        This is NOT the official site of the company or brand identified on the page. The creator of this page is NOT affiliated with the company or brand in any way. DO NOT enter any personal information (such as logins, passwords or credit card numbers) on this site.
      </p>

      <p>---</p>

      <p>
        When reviewing content moderation decisions, we consider information from a variety of sources, including: account profile data, repository contents, activity on collaborative features like Issues, Pull Requests, and Discussions, and information contained in submitted reports/notices, or discovered through our own voluntarily initiated investigations.
      </p>
      {{/is_student_pages}}

      {{^is_student_pages}}
      <p>
        When reviewing content under our {{{mis_dis_information_policy_url}}}, GitHub considers the impact of various factors that may help to orient the viewer, such as whether the content has been provided with clear disclaimers, citations to credible sources, or includes other details that clarify the accuracy of the information being shared. In this case, we deemed it necessary to include a content warning to ensure users were informed before interacting with the content.
      </p>
      {{/is_student_pages}}

      <p>Users visiting the repository will be presented with a dismissible banner containing the notification.</p>

      <p>You may contact us for more information or to request a review of this decision:</p>

      <p>{{{appeal_and_reinstatement_url}}}</p>

      <p>Read more about GitHub's Acceptable Use Policies here: {{{github_help_url}}}.</p>

      <p>{{instructions}}</p>
    MUSTACHE

    TEMPLATE_FOR_INTERSTITIAL_CONTENT_WARNING = <<~MUSTACHE.chomp
      <p>
        Access to the {{repository_name_with_owner}} repository has been limited due to concerns from our
        community that the contents of the repository may include the following:
      </p>

      <p>{{content_warning_reason}}</p>

      <p>
        When making content moderation decisions, we consider information from a variety of sources, including: account profile data, information contained in submitted reports/notices or discovered through our own voluntarily initiated investigations, and context around the contents of the repository. In this case, we deemed it necessary to add a disclaimer and limit the content by giving users the option to opt in before viewing.
      </p>

      <p>
        Going forward, users must be logged in to a GitHub account to view the repository and will be presented with a notice
        related to its content giving them the option of viewing the repository or discovering other content on GitHub.
      </p>

      <p>You may contact us for more information or to request a review of this decision:</p>

      <p>{{{appeal_and_reinstatement_url}}}</p>

      <p>Read more about GitHub's Acceptable Use Policies here: {{{github_help_url}}}.</p>

      <p>{{instructions}}</p>
    MUSTACHE

  end
end
