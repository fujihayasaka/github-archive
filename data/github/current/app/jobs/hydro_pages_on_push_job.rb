# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroPagesOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_pages_on_push

  use_primaries ApplicationRecord::Repositories # page_deployments table

  def perform
    # Skip the enable Pages / build Pages site in the context of a migration
    # either legacy (which should not trigger this code) or via Octoshift (which is in scope here)
    if repository.is_importing?
      return
    end

    publisher = pusher.ghost? ? repository.owner : pusher

    ref_updates.each do |ref_update|
      begin
        ActiveRecord::Base.connected_to(role: :writing) do
          # Only applicable to organizations
          return unless repository.org_members_can_publish_pages?

          return unless repository.pages_branch == short_ref(ref_update.ref)

          if ref_update.deleted?
            repository.handle_pages_branch_delete(ref_update.ref)
            repository.handle_pages_deployments_delete(ref_update.ref)
          else
            repository.rebuild_pages(publisher, git_ref_name: short_ref(ref_update.ref))
          end
        end
      rescue ::Page::PageBuildFailed => boom
        PagesMailer.build_failure(publisher, repository, boom.message).deliver_now
      end
    end
  end

  private

  def short_ref(ref)
    ref.to_s.sub("refs/heads/", "").force_encoding("UTF-8")
  end
end
