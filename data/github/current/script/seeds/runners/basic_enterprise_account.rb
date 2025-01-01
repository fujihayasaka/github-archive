# typed: true
# frozen_string_literal: true

require_relative "../runner"

module Seeds
  class Runner
    class BasicEnterpriseAccount < Seeds::Runner
      def self.help
        <<~HELP
        Seed enterprise accounts with seats_plan_type set to basic.
        HELP
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {
        emu: false,
      })
        if !options[:emu]
          name = Faker::Company.name.first(30)
          slug = name.parameterize
          owner = Seeds::Objects::User.monalisa

          business = ::Business.create!(
            name: name,
            slug: slug,
            seats_plan_type: :basic,
            owners: [owner]
          )
          puts "Created enterprise account with slug #{business.slug}"
        else
          name = Seeds::DataHelper.random_company_slug
          business_hash = self.create_emu_business_hash({
            name: name,
            slug: name.parameterize,
            shortcode: name.parameterize.first(3),
            billing_end_date: 1.year.from_now,
          })
          creator = Business::Creator.new(business_params: business_hash, require_owners: false)

          if creator.valid?
            creator.save!
            business = creator.business
            business.create_and_add_first_emu_owner(email: Seeds::DataHelper.random_email, actor: nil)
            puts "Created emu enterprise account with slug #{business.slug}. Check github.localhost:8025 to create the first admin"
          else
            puts "Failed to create emu basic enterprise account: #{creator.error_message}. Please try running the script again."
          end
        end
      end

      def self.create_emu_business_hash(params)
        {
          name: params[:name],
          slug: params[:slug],
          shortcode: params[:shortcode],
          staff_owned: false,
          seats: 0,
          business_type: "enterprise_managed",
          seats_plan_type: "basic",
          customer_attributes: { billing_end_date: params[:billing_end_date].to_time, name: params[:name], billing_type: "invoice", billing_attempts: 0, term_length: 12 },
          any_length_shortcode_feature_flag_enabled: false,
          owners: []
        }
      end
    end
  end
end
