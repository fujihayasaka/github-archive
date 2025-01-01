# typed: true
# frozen_string_literal: true

module GlobalAdvisories
  class IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include GitHub::Memoizer

    attr_reader :query, :results, :ecosystem_counts, :unreviewed_advisory_count, :reviewed_advisory_count

    def advisories
      return @advisories if defined? @advisories

      advisories = results.map { |result| result["_model"] }
      GitHub::PrefillAssociations.prefill_associations(advisories, { credits: :recipient })

      @advisories = advisories
    end

    def advisory_title(advisory)
      AdvisoryDB::advisory_title(advisory, length: 100)
    end

    def advisory_severity(advisory)
      advisory.severity || "unknown"
    end

    # We only want to show accepted credits, but we avoid using the
    # Vulnerability#credits.accepted scope here because we've already preloaded
    # the entire credits association, so we don't want to trigger a new query.
    def credit_recipients_for_advisory(advisory)
      advisory.credits.filter_map do |credit|
        credit.recipient if credit.accepted?
      end
    end

    def index_path(**params)
      urls.global_advisories_path(params)
    end

    def show_path(advisory)
      urls.global_advisory_path(advisory.ghsa_id)
    end

    def all_unreviewed_filter
      {
        id: "all-unreviewed",
        label: "All unreviewed",
        selected: query.qualifier_selected?(name: :type, value: "unreviewed") && !query.contains_qualifier?(name: :ecosystem),
        count: unreviewed_advisory_count,
        url: index_path(query: query.replace_qualifiers([
          {
            name: :type,
            value: "unreviewed"
          },
          {
            name: :ecosystem,
            value: nil
          },
        ])),
      }
    end

    def all_reviewed_filter
      all_reviewed_index_path_query = query.replace_qualifiers([
        {
          name: :type,
          value: "reviewed"
        },
        {
          name: :ecosystem,
          value: nil
        },
      ])

      {
        id: "all-reviewed",
        label: "All reviewed",
        selected: all_reviewed_selected,
        count: reviewed_advisory_count,
        url: index_path(query: all_reviewed_index_path_query),
      }
    end

    def all_reviewed_selected
      # Ecosystem means not all
      return false if query.contains_qualifier?(name: :ecosystem)
      # Explicitly chosen reviewed
      return true if query.qualifier_selected?(name: :type, value: "reviewed")
      # Implicit default reviewed
      query.query.empty? && !query.contains_qualifier?(name: :type)
    end

    def unreviewed_filters
      [all_unreviewed_filter]
    end

    def ecosystem_filters_for(advisory_type, counts)
      type_selected = query.qualifier_selected?(name: :type, value: advisory_type)

      AdvisoryDB::Ecosystems.public_names.map do |ecosystem|
        selected = type_selected && query.qualifier_selected?(name: :ecosystem, value: ecosystem)
        index_path_query = query.replace_qualifiers([
          {
            name: :type,
            value: advisory_type
          },
          {
            name: :ecosystem,
            value: selected ? nil : ecosystem.downcase
          },
        ])

        {
          id: ecosystem.downcase.gsub(" ", "-"),
          label: AdvisoryDB::Ecosystems.label(ecosystem),
          selected: selected,
          count: counts.fetch(ecosystem.downcase, 0),
          url: index_path(query: index_path_query),
        }
      end
    end

    def mobile_filters
      filters = [all_reviewed_filter].concat(reviewed_ecosystem_filters)

      filters.push({
        divider: true,
        label: "Unreviewed advisories"
      })
      filters.push(all_unreviewed_filter)

      filters
    end

    def reviewed_ecosystem_filters
      return @reviewed_ecosystem_filters if defined? @reviewed_ecosystem_filters

      @reviewed_ecosystem_filters = ecosystem_filters_for("reviewed", ecosystem_counts)
    end

    def reviewed_filters
      [all_reviewed_filter].concat(reviewed_ecosystem_filters)
    end

    def severity_filters
      Vulnerability::SEVERITIES.map do |severity|
        selected = query.qualifier_selected?(name: :severity, value: severity)
        T.let({
          label: severity.capitalize,
          selected: selected,
          severity: severity,
          url: index_path(query: query.replace_qualifier(name: :severity, value: selected ? nil : severity)),
        }, Hash)
      end.unshift({
        label: "All severities",
        selected: !query.contains_qualifier?(name: :severity),
        url: index_path(query: query.replace_qualifier(name: :severity, value: nil)),
      })
    end

    def cwe_filters
      filters = CWE.select(:name, :cwe_id).order(id: :asc).map do |cwe|
        selected = query.qualifier_selected?(name: :cwe, value: cwe.number)
        T.let({
          label: cwe.name,
          id: cwe.cwe_id,
          selected: selected,
          url: index_path(query: query.toggle_qualifier(name: :cwe, value: cwe.number)),
        }, Hash)
      end

      # Show selected filters at top of the list
      filters = filters.partition { |filter| filter[:selected] }.flatten

      filters.unshift({
        label: "All CWEs",
        selected: !query.contains_qualifier?(name: :cwe),
        url: index_path(query: query.replace_qualifier(name: :cwe, value: nil)),
      })
    end

    def sort_directions
      [
        { label: "Newest", query: "published-desc", default: true },
        { label: "Oldest", query: "published-asc" },
        { label: "Recently updated", query: "updated-desc" },
        { label: "Least recently updated", query: "updated-asc" },
      ].map do |sort|
        selected = query.qualifier_selected?(name: :sort, value: sort[:query])
        selected ||= !query.contains_qualifier?(name: :sort) if sort[:default]
        {
          label: sort[:label],
          selected: selected,
          url: index_path(query: query.replace_qualifier(name: :sort, value: selected ? nil : sort[:query])),
        }
      end
    end

    def show_unreviewed_advisories_notice?
      query.qualifier_selected?(name: :type, value: "unreviewed")
    end

    def protip
      @protip ||= protips.sample
    end

    memoize def protips
      protips_list = T.let([{ text: "Advisories are also available from the ", link_text: "GraphQL API", link_href: graphql_protip_url }], T::Array[Hash])

      if logged_in?
        protips_list.push(
          { text: "See the advisories that affect your repositories with", link_text: "involves:@me", link_href: index_path(query: "involves:@me") }
        )
        # Credits are not supported in enterprise.
        unless GitHub.single_or_multi_tenant_enterprise?
          credit_query = "credit:#{current_user.display_login}"

          protips_list.push(
            { text: "See the advisories you've received credit for with ", link_text: credit_query, link_href: index_path(query: credit_query) }
          )
        end
      end

      protips_list
    end

    def graphql_protip_url
      "#{GitHub.developer_help_url}/graphql/reference/queries#securityadvisories"
    end

    def documentation_url
      "#{GitHub.help_url}/github/managing-security-vulnerabilities/browsing-security-vulnerabilities-in-the-github-advisory-database#searching-the-github-advisory-database"
    end
  end
end
