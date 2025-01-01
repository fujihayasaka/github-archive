# typed: true

class AddInactiveSponsorsCountsToUserMetadata < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table(:user_metadata, bulk: true) do |t|
      # We need to store the public count and the private + public count because we show different numbers depending
      # on who is viewing the profile or sponsors listing. If the viewer is the profile/SponsorsListing owner, they
      # see private and public sponsors. Otherwise only public ones are shown.
      #
      # Context and prior art:
      #
      #  * https://github.com/github/github/pull/201363
      #  * https://github.com/github/profile/issues/577
      t.column(
        :inactive_sponsors_public_and_private_count,
        :integer,
        null: false,
        default: 0,
        after: :sponsors_public_and_private_count,
      )
      t.column(
        :inactive_sponsors_count,
        :integer,
        null: false,
        default: 0,
        comment: "Only includes *public* sponsorships",
        after: :inactive_sponsors_public_and_private_count,
      )
      t.column(
        :inactive_sponsoring_public_and_private_count,
        :integer,
        null: false,
        default: 0,
        after: :inactive_sponsors_count,
      )
      t.column(
        :inactive_sponsoring_count,
        :integer,
        null: false,
        default: 0,
        comment: "Only includes *public* sponsorships",
        after: :inactive_sponsoring_public_and_private_count,
      )
    end

    # I'm adding this comment to clarify that these counts only include active
    # sponsorships and are not the total of active + inactive.
    #
    # Passing "from" as well as "to" makes these columns comments reversible
    #
    # See: https://api.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/SchemaStatements.html#method-i-change_column_comment
    change_column_comment(
      :user_metadata,
      :sponsors_public_and_private_count,
      from: nil,
      to: "Only includes *active* sponsorships"
    )
    change_column_comment(
      :user_metadata,
      :sponsoring_public_and_private_count,
      from: nil,
      to: "Only includes *active* sponsorships"
    )
    change_column_comment(
      :user_metadata,
      :sponsors_count,
      from: nil,
      to: "Only includes *active* and *public* sponsorships"
    )
    change_column_comment(
      :user_metadata,
      :sponsoring_count,
      from: nil,
      to: "Only includes *active* and *public* sponsorships"
    )
  end
end
