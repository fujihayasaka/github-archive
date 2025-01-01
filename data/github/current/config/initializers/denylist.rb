# frozen_string_literal: true

module ::GitHub
  ##
  # Please keep this list in alphabetical order
  #
  # If you add a name to this file, make sure you recover the account on dotcom
  # if it's in use.  For help with this, contact @github/support-accounts or
  # check The Hub: https://thehub.github.com/support/compliance/usernames/supporting-username-requests/
  #
  # Note: GitHub.com logins can be reserved via https://admin.github.com/stafftools/reserved_logins

  # Denied for both .com and Enterprise
  global_denylist = %w(
    about
    account
    addons
    admin
    advisories
    any
    api
    apple-app-site-association
    assets
    assets-cdn
    auth
    avatars
    blob
    blog
    bootstrap-instance
    branches
    business
    businesses
    cache
    callbacks
    choose-team
    codesearch
    codespaces
    collection
    collections
    collector-cdn
    comments
    commit
    commits
    compare
    conduit
    contact
    contributing
    ctags
    customer
    customer-stories
    customer-terms
    customers
    dashboard
    dashboards
    dependabot-preview
    dependabots
    dependency-graph-survey
    dependency-insights
    developer-stories
    diff
    discover
    discussion_messages
    discussions
    downloads
    earlyaccess
    edit_repositories
    editors
    enterprise
    enterprises
    enterprise-legal
    error_pages
    events
    explore
    features
    files
    file-servers
    filter-suggestions
    fixtures
    garage
    getting-started
    gist
    gist-assets
    gist-raw
    gists
    github-apps
    github-copilot
    globe
    graphs
    guide
    guides
    help
    help-wanted
    home
    hooks
    identicons
    images
    integration
    introduction
    issues
    javascripts
    jump-to
    languages
    launch
    layouts
    livestreams
    login
    logout
    machine-room
    mailers
    marketplace
    media
    mention
    mentioned
    mentioning
    mentions
    messages
    milestones
    milestones_next
    mona-sans
    navigation
    network
    new
    notices
    notifications
    oauth
    oauth_applications
    organisations
    organizations
    orgs
    owners
    page
    pages
    password_reset
    plugins
    popular
    popularity
    posts
    premium-support
    procurement-legal
    public_keys
    pull_requests
    pulls
    raw
    readme
    recommendations
    relaunch-styles
    releases
    render
    repositories
    repository_cards
    repository_search
    resources
    roadmap
    roadmap-webinar-series
    search
    security-advisories
    security-research-lab
    sessions
    settings
    signin
    signup
    site
    sitemap
    slowtown
    social-impact
    spider-skull-island
    staff
    stafftools
    starred
    stars
    static
    status
    statuses
    storage
    subscriptions
    sudo
    suggest
    suggestion
    suggestions
    support
    suspended
    teams
    thewebsite
    the-website
    timeline
    topic
    topics
    trade-controls
    tree
    u2f
    uploads
    userbox
    username
    users
    web_hooks
    webgl-globe
    wiki
    wiki-raw
    workspaces
  )

  # Only denied for .com
  dotcom_denylist = %w(
    accelerator
    actions-beta
    additional-products-and-features-terms
    advisory-database
    advisory-db
    advisorydatabase
    advisorydb
    anonymous
    answers-github
    answersgithub
    apps
    attributes
    baitshop
    billing
    bounty
    branches
    brand
    buildingthefuture
    c
    camo
    careers
    case-studies
    categories
    central
    certification
    certifications
    changelog
    chat
    cla
    cloud
    cloud-trial
    cmty-gh
    cmty-github
    codeload
    codereview
    comm-gh
    comm-gitHub
    community-gh
    community-github
    companies
    compare
    comunity-gh
    comunity-github
    contact-sales
    contentful-e2e-test-do-not-remove
    contentful-lp-tests
    contexts
    cookbook
    coupons
    customers
    dashboard-feed
    de
    design
    design-blog
    design-system
    design-team
    designs-system
    designs-systems
    develop
    developer
    devops
    devtools
    difftool
    downtime
    editor
    edu
    education
    email
    email-optin
    enterprise-cloud
    enterprise-docs
    enterprise-server
    experience
    featured
    feed_post
    feed_post_playground
    feeds_playground
    forked
    forrester
    forums-github
    forumsgithub
    fr
    frequently-asked-questions
    g1thub
    game-off
    gameoff
    gh-cmty
    gh-comm
    gh-comunity
    git-guides
    github-actions
    github-and-vscode
    github-answers
    github-cmty
    github-comm
    github-community
    github-comunity
    github-debug
    github-design-infrastructure
    github-design-systems
    github-forums
    github-help
    github-social
    github-subprocessors-list
    githubanswers
    githubcommunity
    githubforums
    githubhelp
    gitlfs
    glthub
    halp
    help-github
    helpgithub
    hosting
    identity
    inbox
    indexnow-api-key-placeholder
    individual
    info
    interfaces
    investors
    jobs
    join
    journal
    journals
    lab
    labs
    learn
    legal
    libgit2-ci
    library
    linux
    listings
    lists
    logos
    mac
    maintenance
    malware
    man
    migrating
    mine
    mirrors
    mobile
    new
    news
    newsroom
    non-profits
    none
    nonprofit
    nonprofits
    oauth
    octicons
    octodex
    oembed
    offer
    open-source
    openscripts
    opensource
    packages
    partners
    payments
    personal
    planning-tracking
    plans
    press
    pricing
    professional
    projects
    redeem
    redeem
    reply
    resources-library
    restore
    revert
    save-net-neutrality
    saved
    scraping
    security
    services
    session
    shareholders
    showcases
    site-map
    site-policy
    social
    social-github
    solutions
    spam
    spamurai
    sponsors
    ssh
    stack-instance
    stickers
    store
    stories
    styleguide
    submodules
    subprocessors
    substack
    supplemental-products-and-features
    support-enterprise
    survey-responses
    talks
    teach
    teacher
    teachers
    teaching
    team
    template
    ten
    tenderp
    terms
    thecream
    tos
    tour
    train
    training
    translations
    trending
    trust-center
    universe-2016
    universe-2017
    universe-2018
    universe-2019
    universe-2020
    universe-2021
    universe-2022
    universe-2023
    universe-2024
    universe-2025
    universe-23-waitlist-test
    updates
    upgrading
    visualisation
    visualization
    w
    waitlist
    watching
    webcasts
    webinars
    windows
    works-with
    worldtour
    www0
    www1
    www2
    www3
    www4
    www5
    www6
    www7
    www8
    www9
  )

  # Only denied for enterprise
  enterprise_denylist = %w(
    saml
  )

  proxima_denylist = %w(
    external-app
  )

  DeniedLogins = Set.new
  DeniedLogins.merge(global_denylist)
  DeniedLogins.merge(dotcom_denylist) unless GitHub.enterprise?
  DeniedLogins.merge(enterprise_denylist) if GitHub.enterprise?
  DeniedLogins.merge(proxima_denylist) if GitHub.multi_tenant_enterprise?

  # This doesn't work for Enterprise since we have views like
  # "mobile" and "billing" that we explicitly don't want to be denied
  # in Enterprise. All of the relevant entries have been added
  # above at the time this was committed, but this is left here
  # so it continues being done on .com as a failsafe. Generally
  # speaking doing this automatically seems like a bad idea though.
  unless GitHub.enterprise?
    # all view directories are denied
    Dir[Rails.root + "app/views/*"].each do |dir|
      login = dir.split("/").last
      DeniedLogins << login
    end
  end

  # The Docker API specification requires routes be served under the
  # API path /v2/ and cannot be changed. For running GHES without
  # subdomain isolation mode enabled, this would conflict with the
  # "v2" org if one were to exist, so if docker API routes are reserved,
  # we deny the login and serve the registry from that path instead.
  if GitHub.docker_api_routes_reserved?
    DeniedLogins << "v2"
  end

  # Explicitly allowing these
  DeniedLogins.delete("integrations")
  DeniedLogins.delete("actions")
  # Explicitly allow this even though it matches a view directory
  DeniedLogins.delete("community")

  # all HTTP error codes since static error page files stomp them
  (400..431).each { |code| DeniedLogins << code.to_s }
  (500..511).each { |code| DeniedLogins << code.to_s }
end
