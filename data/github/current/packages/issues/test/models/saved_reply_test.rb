# typed: true
# frozen_string_literal: true

require "test_helper"

class SavedReplyTest < GitHub::TestCase
  fixtures do
    @user       = create :user, login: "authed"
  end

  test "title should be less than 1024 bytes" do
    # this character is a 3 byte unicode sequence
    mb_str = "漢"
    ascii_str = "a"

    reply = create :saved_reply, user: @user
    reply.title = mb_str * 1024
    refute reply.valid?
    refute reply.save
    assert reply.errors[:title].any?

    reply.title = mb_str * 1025
    refute reply.valid?
    refute reply.save
    assert reply.errors[:title].any?

    reply.title = mb_str * 342
    refute reply.valid?
    refute reply.save
    assert reply.errors[:title].any?

    reply.title = mb_str * 341
    assert reply.valid?
    assert reply.save
    refute reply.errors[:title].any?

    reply.title = ascii_str * 1025
    refute reply.valid?
    refute reply.save
    assert reply.errors[:title].any?

    reply.title = ascii_str * 1024
    assert reply.valid?
    assert reply.save
    refute reply.errors[:title].any?
  end

  test "titles should be UTF-8" do
    reply = create :saved_reply, user: @user
    title = "Have a glass of \xF0\x9F\x8D\xB7"
    reply.title = title
    assert reply.save
    reply.reload
    assert_equal Encoding::UTF_8, reply.title.encoding
    assert_equal title, reply.title
  end

  test "bodies should be UTF-8" do
    reply = create :saved_reply, user: @user
    body = "Have a glass of \xF0\x9F\x8D\xB7"
    reply.body = body
    assert reply.save
    reply.reload
    assert_equal Encoding::UTF_8, reply.body.encoding
    assert_equal body, reply.body
  end

  test "prevents excessive number of saved replies" do
    SavedReply.stub_const(:MAX_REPLIES_PER_USER, 3) do
      3.times do
        subject = SavedReply.create(title: "testing", body: "Body", user_id: @user.id)
        assert subject.valid?
      end
      subject = SavedReply.new(title: "testing", body: "Body", user_id: @user.id)
      subject.save

      assert subject.new_record?
      refute subject.valid?
      refute subject.errors[:reply_count].empty?
    end
  end

  test "differentiates templated replies from user-generated replies" do
    default_reply = SavedReply.new(user: @user)
    user_generated_reply = create(:saved_reply, user: @user)

    assert_predicate default_reply, :default?
    refute_predicate user_generated_reply, :default?
  end

end
