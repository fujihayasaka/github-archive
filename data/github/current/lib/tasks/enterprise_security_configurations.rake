# frozen_string_literal: true

namespace :enterprise do
  namespace :security_configurations do
    task on_boot: :environment do
      unless GitHub.enterprise?
        puts "This task can only be run in GitHub Enterprise environments!"
        return
      end

      unbundle_transition = Licensing::GhasUnbundleTransition.where(customer_id: GitHub.global_business.customer_id).order(created_at: :asc).last
      if GitHub.global_business.advanced_security_products_bundled?
        run_rebundle_job(unbundle_transition)
      else
        run_unbundle_job(unbundle_transition)
      end

      EnterpriseUpdateSecurityConfigurationApplicationsJob.perform_now
      puts "Successfully ran Security Configuration on-boot jobs!"
    end

    def run_rebundle_job(transition)
      return if transition.nil? # unbundle transition never ran so there's no need to rebundle
      return if transition.target_sku_state == "bundled" && transition.status == "success" # rebundle transition already ran successfully
      return if transition.target_sku_state == "unbundled" && transition.status != "success" # unbundle transition failed or was cancelled, meaning unbundling never completed and no rebundle is needed

      transition.update!(target_sku_state: "bundled") if transition.target_sku_state == "unbundled"
      transition.enqueue(perform_now: true)
      puts "Successfully ran GHAS rebundle SKU transition job!"
    end

    def run_unbundle_job(transition)
      return if transition&.target_sku_state == "unbundled" && transition.status == "success" # unbundle transition already ran successfully

      if transition.nil?
        transition = Licensing::GhasUnbundleTransition.create!(
          customer_id: GitHub.global_business.customer_id,
          target_sku_state: "unbundled",
          transition_date: Date.current,
          actor: User.ghost,
        )
      else
        transition.update!(target_sku_state: "unbundled") if transition.target_sku_state == "bundled"
      end

      transition.enqueue(perform_now: true)
      puts "Successfully ran GHAS unbundle SKU transition job!"
    end
  end
end
