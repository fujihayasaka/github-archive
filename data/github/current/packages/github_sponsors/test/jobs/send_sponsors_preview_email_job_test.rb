# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.sponsors_enabled?
  class SendSponsorsPreviewEmailJobTest < GitHub::TestCase
    include ActionMailer::TestHelper

    fixtures do
      @listing = create(:sponsors_listing, :for_org)
      @actor = create(:user)
      @repository = create(:private_repository, owner: @listing.sponsorable)
    end

    test "calls now sponsoring" do
      frequency = "recurring"
      welcome_message = "welcome!"
      SponsorsPrimerMailer.expects(:now_sponsoring)
        .once
        .with do |args|
          args[:sponsorable] == @listing.sponsorable &&
            args[:sponsor] == @actor &&
            args[:sponsorship_amount] == "$XX" &&
            args[:tier].welcome_message == welcome_message &&
            args[:tier].frequency == frequency &&
            args[:tier].sponsors_listing == @listing
          args[:tier].repository_id == @repository.id
        end
        .returns(stub(deliver_now: nil))

      SendSponsorsPreviewEmailJob.perform_now(
        actor: @actor,
        sponsors_listing: @listing,
        frequency: frequency,
        welcome_message: welcome_message,
        repository_id: @repository.id
      )
    end

    test "sends the email to the actor" do
      frequency = "recurring"
      welcome_message = "welcome!"

      assert_emails 1 do
        SendSponsorsPreviewEmailJob.perform_now(
          actor: @actor,
          sponsors_listing: @listing,
          frequency: frequency,
          welcome_message: welcome_message,
          repository_id: @repository.id
        )
      end

      mail = ActionMailer::Base.deliveries.last
      assert_equal [@actor.email], mail.to
    end

    test "raises and does not send email if the sponsors-only repository is invalid" do
      invalid_repository = create(:repository)
      SponsorsTier::RepositoryValidator.any_instance.expects(:errors).returns(["some error"])

      assert_no_emails do
        assert_raises(SendSponsorsPreviewEmailJob::InvalidRepository) do
          SendSponsorsPreviewEmailJob.perform_now(
            actor: @actor,
            sponsors_listing: @listing,
            frequency: "recurring",
            welcome_message: "welcome!",
            repository_id: invalid_repository.id
          )
        end
      end
    end
  end
end
