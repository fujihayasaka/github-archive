# frozen_string_literal: true

require "rails_helper"

RSpec.describe "routes not found", type: :request do
  it "HEAD unknown path returns 404" do
    head "/head"

    expect(response).to have_http_status(:not_found)
  end

  it "GET unknown path returns 404" do
    get "/_0d_0ax-sendfile2:/etc/passwd/_2e_2e"

    expect(response).to have_http_status(:not_found)
    expect(response.body).to eq("Not Found")
  end

  it "POST unknown path returns 404" do
    post "/_20../web-inf/"

    expect(response).to have_http_status(:not_found)
    expect(response.body).to eq("Not Found")
  end

  it "PUT unknown path returns 404" do
    put "/:id"

    expect(response).to have_http_status(:not_found)
    expect(response.body).to eq("Not Found")
  end

  it "PATCH unknown path returns 404" do
    patch "/../etc/passwd"

    expect(response).to have_http_status(:not_found)
    expect(response.body).to eq("Not Found")
  end

  it "DELETE unknown path returns 404" do
    delete "/etc/passwd"

    expect(response).to have_http_status(:not_found)
    expect(response.body).to eq("Not Found")
  end
end
