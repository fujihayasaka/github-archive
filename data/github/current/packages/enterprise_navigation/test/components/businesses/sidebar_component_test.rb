# typed: true
# frozen_string_literal: true

require "test_helper"
class  Businesses::SidebarComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include GitHub::Memoizer

  fixtures do
    @user = create(:user)
    @business = create(:business, owners: [@user])
  end

  test "renders" do
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_people,
        groups: [
          EnterpriseNavigation::Group.new(
            links: [EnterpriseNavigation::Link.new(
              link_name: "Members",
              link_path: urls.people_enterprise_path(@business),
              highlight: :business_people,
              icon: :people
            )]
          )
        ],
        test_selector: "business-sidebar",
      ),
      allowed_queries: 1,
    )
    assert_test_selector("business-sidebar")
    assert_selector(".ActionListItem--navActive", text: "Members")
    refute_selector(".ActionList-sectionDivider")
  end

  test "renders links in groups with dividers between groups" do
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_admins,
        groups: [
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: :people
              ),
              EnterpriseNavigation::Link.new(
                link_name: "Administrators",
                link_path: urls.enterprise_admins_path(@business),
                highlight: %i(
                  business_admins
                ),
                icon: :law
              )
            ]
          ),
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Enterprise teams",
                link_path: urls.enterprise_teams_path(@business),
                highlight: %i(
                  business_teams
                ),
                icon: :people
              )
            ],
          ),
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Security managers",
                link_path: urls.enterprise_security_managers_path(@business),
                highlight: %i(business_security_managers),
                icon: :"shield-lock"
              )
            ]
          )
        ],
        test_selector: "business-sidebar",

      ),
      allowed_queries: 1,
    )
    assert_selector(".ActionListItem--navActive", text: "Administrators")
    assert_selector(".ActionList-sectionDivider", count: 2)
    refute_selector(".business-sidebar-flat")
  end

  test "supports flat groups that do not have leading divider" do
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_admins,
        groups: [
          EnterpriseNavigation::Group.new(
            type: EnterpriseNavigation::GroupType::FLAT,
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: :people
              ),
              EnterpriseNavigation::Link.new(
                link_name: "Administrators",
                link_path: urls.enterprise_admins_path(@business),
                highlight: %i(
                  business_admins
                ),
                icon: :law
              )
            ]
          ),
          EnterpriseNavigation::Group.new(
            type: EnterpriseNavigation::GroupType::FLAT,
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Enterprise teams",
                link_path: urls.enterprise_teams_path(@business),
                highlight: %i(
                  business_teams
                ),
                icon: :people
              )
            ],
          ),
          EnterpriseNavigation::Group.new(
            type: EnterpriseNavigation::GroupType::FLAT,
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Security managers",
                link_path: urls.enterprise_security_managers_path(@business),
                highlight: %i(business_security_managers),
                icon: :"shield-lock"
              )
            ]
          )
        ],
        test_selector: "business-sidebar",

      ),
      allowed_queries: 1,
    )
    assert_selector(".ActionListItem--navActive", text: "Administrators")
    refute_selector(".ActionList-sectionDivider")
  end

  test "supports flat groups that do not have leading divider and work with folding groups" do
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_admins,
        groups: [
          EnterpriseNavigation::Group.new(
            type: EnterpriseNavigation::GroupType::FOLDING_WITH_DIVIDER,
            name: "Members & Administrators",
            icon: :people,
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: nil
              ),
              EnterpriseNavigation::Link.new(
                link_name: "Administrators",
                link_path: urls.enterprise_admins_path(@business),
                highlight: %i(
                  business_admins
                ),
                icon: nil
              )
            ]
          ),
          EnterpriseNavigation::Group.new(
            type: EnterpriseNavigation::GroupType::FLAT,
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: :people
              ),
              EnterpriseNavigation::Link.new(
                link_name: "Administrators",
                link_path: urls.enterprise_admins_path(@business),
                highlight: %i(
                  business_admins
                ),
                icon: :law
              )
            ]
          ),
        ],
        test_selector: "business-sidebar",

      ),
      allowed_queries: 1,
    )
    assert_selector(".ActionListItem--navActive", text: "Administrators")
    # note that dividers are automatically added by the primer component between different groups, and have to be
    # visually hidden in some cases see businesses.scss
    assert_selector(".ActionList-sectionDivider", count: 2)
    assert_selector(".business-sidebar-flat")
  end

  test "does not render dividers for empty groups" do
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_admins,
        groups: [
          EnterpriseNavigation::Group.new(
            links: [],
          ),
          EnterpriseNavigation::Group.new(
            links: [],
          ),
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Administrators",
                link_path: urls.enterprise_admins_path(@business),
                highlight: %i(
                  business_admins
                ),
                icon: :law
              )
            ]
          )
        ],
        test_selector: "business-sidebar",

      ),
      allowed_queries: 1,
    )
    assert_selector(".ActionListItem--navActive", text: "Administrators")
    refute_selector(".ActionList-sectionDivider")
  end

  test "can select an item given a list of highlights" do
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_super_admins,
        groups: [
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: :people
              ),
              EnterpriseNavigation::Link.new(
                link_name: "Administrators",
                link_path: urls.enterprise_admins_path(@business),
                highlight: %i(
                  business_admins
                  business_super_admins
                  business_managers
                ),
                icon: :law
              )
            ]
          )
        ],
        test_selector: "business-sidebar",
      ),
      allowed_queries: 1,
    )
    assert_selector(".ActionListItem--navActive", text: "Administrators")
  end

  test "shows private preview label" do
    enable_feature_flag(:lifecycle_label_name_updates, @user)
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_people,
        groups: [
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: :people,
                label: EnterpriseNavigation::Label::PRIVATE_PREVIEW
              )
            ]
          )
        ],
        test_selector: "business-sidebar",
      ),
      allowed_queries: 1,
    )
    assert_text("Private preview")
  end

  test "shows alpha label" do
    disable_feature_flag(:lifecycle_label_name_updates, @user)
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_people,
        groups: [
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: :people,
                label: EnterpriseNavigation::Label::PRIVATE_PREVIEW
              )
            ],
          ),
        ],
        test_selector: "business-sidebar",
      ),
      allowed_queries: 1,
    )
    assert_text("Alpha")
  end

  test "shows preview label" do
    enable_feature_flag(:lifecycle_label_name_updates, @user)
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_people,
        groups: [
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: :people,
                label: EnterpriseNavigation::Label::PREVIEW
              )
            ],
          ),
        ],
        test_selector: "business-sidebar",
      ),
      allowed_queries: 1,
    )
    assert_text("Preview")
  end

  test "shows beta label" do
    disable_feature_flag(:lifecycle_label_name_updates, @user)
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_people,
        groups: [
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: :people,
                label: EnterpriseNavigation::Label::PREVIEW
              )
            ],
          ),
        ],
        test_selector: "business-sidebar",
      ),
      allowed_queries: 1,
    )
    assert_text("Beta")
  end

  test "renders an icon" do
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_people,
        groups: [
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: :people,
                label: EnterpriseNavigation::Label::PREVIEW
              )
            ],
          ),
        ],
        test_selector: "business-sidebar",
      ),
      allowed_queries: 1,
    )
    assert_selector(".octicon-people")
  end

  test "supports folding groups" do
    enable_feature_flag(:lifecycle_label_name_updates, @user)
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_admins,
        groups: [
          EnterpriseNavigation::Group.new(
            type: EnterpriseNavigation::GroupType::FOLDING,
            name: "Members & Administrators",
            icon: :people,
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: nil
              ),
              EnterpriseNavigation::Link.new(
                link_name: "Administrators",
                link_path: urls.enterprise_admins_path(@business),
                highlight: %i(
                  business_admins
                ),
                icon: nil
              )
            ]
          ),
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Enterprise teams",
                link_path: urls.enterprise_teams_path(@business),
                highlight: %i(
                  business_teams
                ),
                icon: :people
              )
            ],
          ),
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Security managers",
                link_path: urls.enterprise_security_managers_path(@business),
                highlight: %i(business_security_managers),
                icon: :"shield-lock"
              )
            ]
          )
        ],
        test_selector: "business-sidebar",

      ),
      allowed_queries: 1,
    )
    assert_selector(".business-sidebar-flat")
    assert_selector(".ActionListItem--hasSubItem", text: "Members & Administrators")
    assert_selector(".ActionListItem--navActive", text: "Administrators")
    # note that dividers are automatically added by the primer component between different groups, and have to be
    # visually hidden in some cases see businesses.scss
    assert_selector(".ActionList-sectionDivider", count: 3)
  end

  test "folding group with preview label" do
    enable_feature_flag(:lifecycle_label_name_updates, @user)
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_admins,
        groups: [
          EnterpriseNavigation::Group.new(
            type: EnterpriseNavigation::GroupType::FOLDING,
            name: "Members & Administrators",
            icon: :people,
            label: EnterpriseNavigation::Label::PREVIEW,
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: nil
              ),
              EnterpriseNavigation::Link.new(
                link_name: "Administrators",
                link_path: urls.enterprise_admins_path(@business),
                highlight: %i(
                  business_admins
                ),
                icon: nil
              )
            ]
          ),
        ],
        test_selector: "business-sidebar",

      ),
      allowed_queries: 1,
    )

    assert_selector(".ActionListItem--hasSubItem .ActionListItem-visual--trailing", text: "Preview")
  end

  test "folding group with private preview" do
    enable_feature_flag(:lifecycle_label_name_updates, @user)
    render_inline(
      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_admins,
        groups: [
          EnterpriseNavigation::Group.new(
            type: EnterpriseNavigation::GroupType::FOLDING,
            name: "Members & Administrators",
            icon: :people,
            label: EnterpriseNavigation::Label::PRIVATE_PREVIEW,
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: nil
              ),
              EnterpriseNavigation::Link.new(
                link_name: "Administrators",
                link_path: urls.enterprise_admins_path(@business),
                highlight: %i(
                  business_admins
                ),
                icon: nil
              )
            ]
          ),
        ],
        test_selector: "business-sidebar",

      ),
      allowed_queries: 1,
    )
    assert_selector(".ActionListItem--hasSubItem .ActionListItem-visual--trailing", text: "Private preview")
  end

  test "supports folding groups with leading divider" do
    enable_feature_flag(:lifecycle_label_name_updates, @user)
    render_inline(

      Businesses::SidebarComponent.new(
        user: @user,
        business: @business,
        title: "Test Sidebar",
        selected_link: :business_admins,
        groups: [
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Enterprise teams",
                link_path: urls.enterprise_teams_path(@business),
                highlight: %i(
                  business_teams
                ),
                icon: :people
              )
            ],
          ),
          EnterpriseNavigation::Group.new(
            type: EnterpriseNavigation::GroupType::FOLDING_WITH_DIVIDER,
            name: "Members & Administrators",
            icon: :people,
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Members",
                link_path: urls.people_enterprise_path(@business),
                highlight: :business_people,
                icon: nil
              ),
              EnterpriseNavigation::Link.new(
                link_name: "Administrators",
                link_path: urls.enterprise_admins_path(@business),
                highlight: %i(
                  business_admins
                ),
                icon: nil
              )
            ]
          ),
          EnterpriseNavigation::Group.new(
            links: [
              EnterpriseNavigation::Link.new(
                link_name: "Security managers",
                link_path: urls.enterprise_security_managers_path(@business),
                highlight: %i(business_security_managers),
                icon: :"shield-lock"
              )
            ]
          )
        ],
        test_selector: "business-sidebar",

      ),
      allowed_queries: 1,
    )
    refute_selector(".business-sidebar-flat")
    assert_selector(".ActionListItem--hasSubItem", text: "Members & Administrators")
    assert_selector(".ActionListItem--navActive", text: "Administrators")
    # note that dividers are automatically added by the primer component between different groups, and have to be
    # visually hidden in some cases see businesses.scss
    assert_selector(".ActionList-sectionDivider", count: 3)
  end

  sig { returns(UrlHelpers) }
  memoize def urls
    T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
  end
end
