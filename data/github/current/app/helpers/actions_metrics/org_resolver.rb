# typed: true
# frozen_string_literal: true

module ActionsMetrics::OrgResolver
  def resolve_orgs(items)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    org_ids = items.pluck(:owner_id).uniq.to_a.compact
    return unless org_ids&.length > 0

    orgs = Array.new
    orgs = Organization.where(id: org_ids)
    org_map = orgs.index_by { |r| r.id }

    # add org information to each item
    items.each do |item|
      org = org_map[item[:owner_id]]
      unless org.nil?
        item[:org] = {
          id: org.id,
          name: org.display_login,
          url: "/#{org.display_login}"
        }
      end
    end

    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed_time = (end_time - start_time) * 1_000
    GitHub.logger.info("resolve_orgs complete", {
      "code.namespace" => "ActionsMetrics::OrgResolver",
      "code.function" => "resolve_orgs",
      "gh.actions_metrics.org_resolver.resolve_orgs.time" => elapsed_time,
    })
    GitHub.dogstats.distribution("actions_metrics.org_resolver.resolve_orgs.dist.time", elapsed_time)
  end

  def add_org_info(items, offset = 0)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    unless items.nil? || items.length == 0
      if Rails.env.development?
        # replace with fake org because the org ids wont resolve to anything
        items.each_with_index do |item, index|
          append = index + offset + 1
          item[:org] = get_fake_org(append)
        end
      else
        resolve_orgs(items)
      end
    end
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed_time = (end_time - start_time) * 1_000
    GitHub.logger.info("add_org_info complete", {
      "code.namespace" => "ActionsMetrics::OrgResolver",
      "code.function" => "add_org_info",
      "gh.actions_metrics.org_resolver.add_org_info.time" => elapsed_time,
    })
    GitHub.dogstats.distribution("actions_metrics.org_resolver.add_org_info.dist.time", elapsed_time)
  end

  def get_fake_org(append)
    name = "fake-org-#{append}"
    url = "#"

    org = {
      id: -1,
      name: name,
      url: url
    }
  end
end
