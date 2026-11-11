# typed: true
# frozen_string_literal: true

require_relative "../runner"
require_relative "actions_repos"
require_relative "marketplace_partner_action_listings"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class FeaturedMarketplaceActions < Seeds::Runner
      DEFAULT_COUNT = 10
      DEFAULT_PARTNER_SAMPLE_SIZE = 5
      DEFAULT_FEATURED_COUNT = 5

      def self.help
        <<~HELP
        Seeds marketplace action listings (via actions_repos and marketplace_partner_action_listings)
        and then marks a handful of them as featured so the Editor::ActionsController#index featured
        branch returns data in development.
        HELP
      end

      def self.run(options = {})
        count = options[:count] || DEFAULT_COUNT
        partner_sample_size = options[:partner_sample_size] || DEFAULT_PARTNER_SAMPLE_SIZE
        featured_count = options[:featured_count] || DEFAULT_FEATURED_COUNT

        puts "-> Seeding marketplace actions from the actions org (count: #{count})"
        Seeds::Runner::ActionsRepos.execute(
          count: count,
          login: options[:login],
          use_marketplace: true,
        )

        puts "-> Seeding partner marketplace action listings (sample_size: #{partner_sample_size})"
        Seeds::Runner::MarketplacePartnerActionListings.execute(
          sample_size: partner_sample_size,
        )

        puts "-> Marking #{featured_count} listed actions as featured"
        featured_ids = ::RepositoryAction.listed.where(featured: false)
          .order(Arel.sql("RAND()")).limit(featured_count).pluck(:id)
        updated = ::RepositoryAction.where(id: featured_ids).update_all(featured: true)
        puts "-> Marked #{updated} action(s) as featured"

        puts "-> Repairing RepositoryActions search index..."
        # These calls are stubbed in the test environment; any changes here
        # must be covered by test/script/seeds/runners/featured_marketplace_actions_test.rb.
        elastomer_app = Elastomer::App.new
        repository_actions_index = elastomer_app.primary_index(Elastomer::Indexes::RepositoryActions)
        elastomer_app.load_data(repository_actions_index)
      end
    end
  end
end
