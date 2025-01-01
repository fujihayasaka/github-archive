# typed: true
# frozen_string_literal: true

require "set"

class Contributors
  # Internal: Array of repository ids for which shortlog cannot be computed in a
  # web request (ie: usually take longer than gitrpc timeout). Feel free to add
  # more as they crop up or remove any if we improve shortlog or some up with a
  # new means of generating this contributor data.
  SHORTLOG_NOT_WEB_COMPUTABLE_REPOSITORY_IDS = if GitHub.enterprise?
    Set.new.freeze
  else
    Set.new([
      44208548, # 01org/Igvtg-kernel
      12446909, # 01org/XenGT-Preview-kernel
      43565168, # 01org/linux-apollolake-i
      16846492, # 01org/prd
      17629145, # ARM-software/linux
       1609280, # AltraMayor/XIA-for-Linux
      17921159, # AppliedMicro/ENGLinuxLatest
      39620161, # AppliedMicro/xgene-next
      46619923, # Asus-T100/kernel
      44315164, # Basler/linux-usb-zerocopy
      30661243, # BenRomer/unisys
      40488376, # BroadGen/linux-xlnx
      39087375, # Broadcom/arm64-linux
      35756714, # Broadcom/brcm80211
      28927116, # Broadcom/cygnus-linux
      48673763, # Caesar-github/rockchip
      39470871, # CalvinFernandez/testgit
       2493125, # Canonical-kernel/Ubuntu-kernel
      44330607, # CogentEmbedded/linux-zodiac
      29562114, # CumulusNetworks/linux-apd
      37095250, # CumulusNetworks/net-next
      45493669, # DespairFactor/angler
      45493679, # DespairFactor/bullhead
      19836773, # DigilentInc/Linux-Digilent-Dev
      34005291, # EmbeddedAndroid/linux
      30717152, # Evisceration/linux-kernel
      38893534, # Ferroin/linux
      27210002, # Flipkart/linux
      13045768, # Gandi/ktrill
      11599836, # Gateworks/linux-imx6
      44708657, # GoinsWithTheWind/drm-prime-sync
      34801949, # IntelTSD/adit_bsp_byt-kernel_tsd
      37707716, # Jianwei-Wang/linux-drm-fsl-dcu
      45846071, # Kamalheib/soft-roce
      21481110, # KenanSulayman/heartbeat
       5077426, # LITMUS-RT/litmus-rt
      45382903, # Linutronix/linux
      37495539, # Linutronix/ti-linux-kernel
      31952907, # MISL-EBU-System-SW/lsp-public
      12470566, # Marvell-Semi/PXA168_kernel
      40904050, # MentorEmbedded/linux-apl-p
       8289173, # MentorEmbedded/linux-mel
      45263644, # MicrochipTech/linux-pic32
      42051876, # Mrcl1450/f2fs
      38722664, # NextThingCo/CHIP-linux
       3232337, # NigelCunningham/tuxonice-kernel
      36571529, # NuxiNL/linux
      22418740, # OpenChannelSSD/linux
       5296498, # PKRoma/linux
      41249477, # PKRoma/linux-bcache
      27715330, # Phant0mas/linux
      42801852, # Planet15/linux
      46408347, # Quantenna/qtn-kernel
      21661121, # RSpliet/kernel-nouveau-nv50-pm
      34704105, # Rashed97/caf-kernel-msm-3.10
      36669033, # Rashed97/caf-kernel-msm-3.18
      21703605, # RobertCNelson/linux-stable-rcn-ee
      20300219, # RobertCNelson/ti-linux-kernel
      33163609, # RockchipOpensourceCommunity/kernel-rockchip-next
       9749619, # Sabayon/kernel
      29025022, # SoftRoCE/rxe-dev
      48840549, # SolidRun/linux-stable
       2499415, # TI-OpenLink/wl18xx
      48012503, # Taeung/linux-perf
      24619405, # Taeung/tip
      35550395, # TeamFahQ/kernel_linux_next
      30072036, # Tessares/mproxy_kernel
      35900676, # TimesysGit/advantech-linux-bx60
      46372334, # TimesysGit/preferred-utilities-linux
      18414150, # ValveSoftware/steamos_kernel
      26152911, # Varcain/linux_ARMv7M
      40245486, # Whissi/linux-stable
      48558572, # Wootever/kernel_i7_stylus
       8890645, # Xilinx/linux-xlnx
      47892993, # Zkin/pf-kernel-updates
      22427564, # abhijeet-dev/linux-samsung
       5842601, # alpinelinux/linux-stable-grsec
      34010061, # altera-opensource/linux-socfpga
       6124250, # analogdevicesinc/linux
      15027831, # andersson/kernel
      46854367, # andreamerello/linux-zynq-stable
      43967853, # android-x86-mirror/kernel_common
      18809516, # anoever/thunderbolt
      41822694, # arnoldthebat/linux-stable
      45133761, # atalax/linux
      48193588, # avinashpqtn/qtn-kernel
      14950572, # backbone/backbone-sources
      45991026, # bas-t/linux-stable
      37029347, # bas-t/media_tree
      47608613, # bbrezillon/linux-0day
      25880782, # bbrezillon/linux-marvell
      15204088, # beagleboard/devicetree-source
      13096677, # beagleboard/linux
      25341303, # beaulebens/keyring
       6545390, # bendikro/net-next
      47744897, # bhundven/linux-quark
      39084690, # bigzz/f2fs
      46074200, # bjdooks-ct/amlogic-kernel
      46515456, # blogic/net-next
      15821657, # bluecmd/or1k-linux
      38370535, # brgl/linux
       1366049, # bvanassche/linux
       2343211, # ceph/ceph-client
      25691781, # cfinke/keyring
       4453072, # changbindu/linux-ok6410
      43595865, # charles1018/The-f2fs-filesystem
      30354941, # chaseyu/f2fs-dev
      44978987, # claudioscordino/linux-xlnx
       9964928, # cminyard/linux-live-app-coredump
      35160932, # codeaurora-unoffical/linux-msm
      48494355, # columbia/linux-el2
      34128413, # compudj/linux-dev
      12504930, # contactless/linux
      34916542, # crazycat69/linux_media
       9207286, # crosswalk-project/chromium-crosswalk
      33260289, # cschaufler/smack-next
       3809818, # danielschwierzeck/linux
      37207692, # davejiang/linux
      44830690, # ddalessa/kernel
      47513611, # deepa-hub/vfs
      48229602, # dianlujitao/CAF_kernel_msm-3.10
      20412988, # digetx/picasso-kernel
      38626856, # digetx/picasso_upstream_support
      46492190, # dininek/linux-stable-rcn-ee
       8305217, # direct-code-execution/net-next-sim
      48140901, # dtwood/kernel
      47304919, # dwindsor/linux-stable
      39468347, # effenel/kernel
      45384020, # emlid/CHIP-linux
      41118558, # emvn-fabrics/devel
      38497849, # enclustra-bsp/altera-linux
      38497539, # enclustra-bsp/xilinx-linux
      19992892, # endlessm/linux
      45350603, # erlerobot/CHIP-linux
      21402824, # ev3dev/ev3-kernel
      41191128, # flaming-toast/unrm
      45482810, # flar2/angler
      45489294, # franciscofranco/angler
      27861010, # fyu1/linux
      12040130, # g0v-data/mirror
       7521817, # gcwnow/linux
      40437196, # gentoo/gentoo-gitmig-20150809-draft
       7690059, # git-portage/git-portage
      31741614, # goldwynr/kernel
      13300800, # google/capsicum-linux
      44673582, # gpkulkarni/linux-arm64
      10774608, # guillaumelecerf/linux
       6435034, # gumstix/linux
      27279260, # hanipouspilot/ubuntu-fixes
      35061757, # helen-fornazier/opw-staging
      43904105, # henrix/beagle-linux
      33294346, # hisilicon/kernel-dev
      21420501, # hisilicon/linux-hisi
      45663832, # horms/renesas-priv
      44700099, # iConsole/Console-OS_kernel_common
      28615447, # ibanezchen/linux-8173
      43722756, # jakew02/sp3-linux
       5320694, # jcmvbkbc/linux-xtensa
      47320373, # jeffmerkey/linux-stable
       2821145, # jlelli/sched-deadline
      15808873, # jmontleon/fedora-cubox-i_hb
      47344395, # jmontleon/fedora-solidrun
      20493254, # joergroedel/linux-iommu
      11777431, # joeyli/linux-s4sign
       5405856, # jonmason/ntb
      39576501, # jpirko/mlxsw
      40720874, # jpirko/rocker_bpf
      44123846, # jrfastab/hardware_maps
      28781511, # jrfastab/rocker-net-next
       1270680, # jthornber/linux-2.6
      38493762, # justinshreve/keyring
      47522170, # k123suz/linux-xlnx
       2390223, # kgene/linux-samsung
      39512995, # kholk/kernel-msm
      46032816, # krzk/tizen-tv-rpi-linux
      45436105, # kula85/perf-sqlite3
       9442980, # kvalo/ath10k
      26977563, # kwight/keyring
      48512303, # lab11/bluetooth-next
      44268373, # lambdadroid/kernel_msm-3.10
      24234026, # libos-nuse/net-next-nuse
      38111170, # links234/qr-linux-kernel
      45539991, # linusw/linux-bfq
      46233839, # linusw/linux-mt7630e
      25129756, # linux-scraping/linux-grsecurity
      11809145, # linux-shield/kernel
      21647974, # linux-wpan/linux-wpan
       8766755, # linux-wpan/linux-wpan-next
       2398295, # linux4sam/linux-at91
      11200367, # ljalves/linux_media
      27226541, # logicbricks/linux-xlnx
      49349829, # lorenzo-stoakes/linux-historical
      33152446, # lsigithub/axxia_yocto_linux_3.19
      39468741, # lsigithub/axxia_yocto_linux_4.1
      39468764, # lsigithub/axxia_yocto_linux_4.1_private
      39468819, # lsigithub/axxia_yocto_linux_4.1_pull
      37194010, # lucabe72/linux-reclaiming
      24066225, # majorleaguesoccer/opta
      25330948, # markyzq/kernel-drm-rockchip
      45698421, # martinbrandenburg/linux
      34660216, # masahir0y/linux-yamada
      40194248, # mathworks/xilinx-linux
      36547178, # maurossi/linux
      20399307, # mbgg/linux-mediatek
      13855856, # mcdope/pf-kernel
      31455745, # mcoquelin-stm32/linux
       5825723, # michael2012z/myKernel
      49441320, # mikechristie/linux-kernel
      14923563, # minaco2/git-portage
      17227535, # minipli/linux-grsec
      26221348, # mjawaids/woocommerce-variation-sorting-in-admin
      49601144, # mschlaeffer/ubuntu-kernel-with-tuxonice
      41738791, # mtitinger/linux-pm
       4749289, # multipath-tcp/mptcp
      26328907, # multipath-tcp/mptcp_net-next
      25585160, # nekromant/linux
       7429579, # nmenon/linux-2.6-playground
      47342893, # nopeppermint/linux-socfpga
      39689442, # notro/linux-staging
      44660834, # open-estuary/kbase
      41137501, # open-estuary/kernel
      27374238, # openSUSE/kernel
      39613183, # osmc/vero-linux
      31810417, # pali/linux-n900
      11091036, # pantoniou/linux-beagle-track-mainline
       8758888, # patjak/drm-gma500
      27601596, # patrykk/linux-udoo
      16688309, # pcarrier/linux
       1237969, # penberg/linux-kvm
      30962704, # petermolnar/keyring
        455159, # pfactum/pf-kernel
      40876773, # philenotfound/linux-stable-15khz
      21528451, # pkirchhofer/nsa325-linux-upstream
      28528167, # pratyushanand/linux
      47215928, # puppybane/linux-cyrus
      13783199, # rapier1/web10g
      44583799, # rockchip-linux/kernel
      45309249, # rperier/linux-meson
      22140031, # rubiojr/surface3-kernel
      39387605, # sagigrimberg/linux
      25712112, # sbates130272/linux-donard
       6049098, # scheib/chromium
      26130541, # segment-routing/sr-ipv6
      48115226, # semihalf-nowicki-tomasz/linux
       9763176, # sfjro/aufs3-linux
      31196860, # sfjro/aufs4-linux
      13817011, # sgstreet/linux-socfpga
      46883520, # sguiriec/linux-audio
      31006976, # shobhitka/linux-kernel
      45032652, # shubhangi-shrivastava/drm-intel-nightly
      42521828, # siemens/linux-ipipe
      34012298, # siskin/bluetooth-next
      22894559, # slongerbeam/mediatree
      24188676, # smartyg/amazing-post-widget
      46725781, # smatyukevich/qtn-kernel
       9492125, # sonyxperiadev/kernel
      23574294, # sprdlinux/kernel
      28604936, # ssuthiku/linux
      44084259, # sudipm-mukherjee/linux-test
      35208486, # sudipm-mukherjee/parport
       2148061, # svenkatr/linux
      45273816, # synexxus/synnix
      27153208, # tgraf/net-next
      48123181, # thisway23/linux-kvm-arm
      48136350, # tiagovignatti/drm-intel
      39113582, # tinyclub/linux-loongson-community
      49208381, # tobiasjakobi/linux-odroid
      47022804, # tomzo/pf-kernel
       2325298, # torvalds/linux
       4436221, # tradingtechnologies/debesys
      24284093, # trsqr/media_tree
      32040994, # tzanussi/linux-yocto-micro-3.19
      37383888, # uniphier/linux-unph
      46058030, # unusual-thoughts/linux-xps13
      11886548, # uoaerg/linux-dccp
      42647434, # updateing/openwrt-r6220-kernel
      46344569, # varigit/VAR-SOM-AMx3-Kernel-4-1
      31901838, # vathpela/linux-esrt
      45143705, # vilhelmgray/linux-gpio
      33725616, # vsyrjala/linux
      29883227, # weiny2/linux-kernel
      47747371, # wenhulove333/LinuxKernelStable
      47928913, # winsock/linux-next-st8
      25465746, # woodsts/linux-stable
      13384947, # xobs/novena-linux
      42618491, # yi9/orangefs
      49455323, # yyu168/linux
       2465166, # zen-kernel/zen-kernel
    ]).freeze
  end

  # Private: Cached sentinel value for repositories where the shortlog cannot
  # be computed.
  NOT_COMPUTABLE_SENTINEL = :not_computable

  UncomputableShortlog = Class.new(StandardError)

  def self.count_cache_key(repository)
    "repository:contributors:v2:#{repository.id}:size"
  end

  attr_reader :repository, :ignore_merge_commits, :mailmap

  class Response
    class ComputedPredicateNotChecked < StandardError
      DEFAULT_MESSAGE = "Response value cannot be used without first checking if the value was computed using the computed? predicate method"

      def initialize(message = DEFAULT_MESSAGE)
        super
      end
    end

    def initialize(value: nil, computed:)
      @value = value
      @computed = computed
      @computed_predicate_checked = false
    end

    def computed?
      @computed_predicate_checked = true
      @computed
    end

    def value
      unless @computed_predicate_checked
        raise ComputedPredicateNotChecked
      end

      @value
    end
  end

  class AllResponse < Response
    # value - The Array result returned by #all if it could be computed.
    # computed - The Boolean value that informs callers as to whether the real
    #            shortlog could be computed or if they should show an error to
    #            the user.
    def initialize(value: [], computed:)
      super
    end
  end

  class CountResponse < Response
    # value - The Integer or Symbol result returned by #count if it could
    #         be computed. Symbol is used for when value not computable.
    def initialize(value)
      if value == NOT_COMPUTABLE_SENTINEL
        @value = 0
        @computed = false
      else
        @value = value
        @computed = true
      end
      super(value: @value, computed: @computed)
    end
  end

  def initialize(repository, not_computable_ids: SHORTLOG_NOT_WEB_COMPUTABLE_REPOSITORY_IDS, ignore_merge_commits: false, mailmap: true)
    @repository = repository
    @not_computable_ids = not_computable_ids
    @ignore_merge_commits = ignore_merge_commits
    @mailmap = mailmap
  end

  def shortlog_not_computable?
    @not_computable_ids.include?(@repository.id)
  end

  # Find all GitHub users (and optionally non-users) who have contributed to
  # this repository.
  #
  # with_anon     - Boolean indicating whether to include anonymous, non-GitHub
  #                 authors (default: false).
  # email_ limit  - Integer indicating the maximum number of email addresses
  #                 that this method should process from the given Array (default: none).
  # viewer        - The current user, used for spam-filtering purposes; a User or nil
  #
  #
  # Returns an Array in the format of
  #   [ User or Hash of :email and :name, # of commits ]
  def all(with_anon: false, email_limit: nil, viewer: nil, skip_private_profiles: false)
    authors = mailmap ? counts_by_author : counts_by_author_log

    author_emails = authors.keys.map! { |key| key[:email] }
    author_emails = author_emails.first(email_limit) if email_limit

    business = @repository.enterprise_managed_business
    user_map = User.find_by_emails(author_emails, business: business, skip_private_profiles: skip_private_profiles).transform_keys(&:downcase)

    contribs = Hash.new(0)
    authors.each do |hash, count|
      email = hash[:email].downcase

      if user = user_map[email]
        # Do not include spammy users for all viewers except the case
        # where the viewer is the spammy user
        next if user.spammy? && user != viewer
        contribs[user] += count
      elsif with_anon
        name = hash[:name].strip
        contribs[{ email: email, name: name }] = count
      end
    end

    sorted_contribs = contribs.sort_by { |_user, count| -count }
    AllResponse.new(value: sorted_contribs, computed: true)
  rescue GitRPC::Timeout, GitRPC::CommandFailed, UncomputableShortlog
    AllResponse.new(computed: false)
  end

  # Public: Returns the number of contributors to this project that exist on
  # github. Attempts to pull from cache. If uncached, it will attempt to compute
  # value and cache the compuated value.
  #
  # If the size cannot be computed, a sentinel value is cached to avoid trying
  # to recompute values that cannot be computed.
  def count
    value = GitHub.cache.fetch(count_cache_key, ttl: 3.hours) do
      response = all
      if response.computed?
        response.value.length
      else
        NOT_COMPUTABLE_SENTINEL
      end
    end

    CountResponse.new(value)
  end

  # Public: Returns a CountResponse instance only if the contributor
  # size count is in cache. If not in cache, nil is returned. You should
  # normally just use count which does the normal cache
  # fetch/generate. The only time you might want this method is when you plan on
  # populating cache if not present, but not from where you want to use the
  # cache (ie: in web you want to show cache if available else ajax in uncached)
  def count_from_cache
    if value = GitHub.cache.get(count_cache_key)
      CountResponse.new(value)
    end
  end

  def count_cache_key
    self.class.count_cache_key(@repository)
  end

  def shortlog_cache_key
    parts = ["repository", "shortlog", "v1", repository.id]
    parts << "no-merges" if ignore_merge_commits
    parts.join(":")
  end

  private

  # Transforms the git-shortlog into an array of contribution info.
  #
  # Returns a Hash, indexed by Git author info:
  #
  #   {:email => ..., :name => ...} => 123
  def counts_by_author
    shortlog.split("\n").each_with_object({}) do |line, authors|
      count, author = line.split("\t")

      if author =~ /(.+?)<(.+)>/
        authors[{ name: $1, email: $2 }] = count.strip.to_i
      end
    end
  end

  # Like counts_by_author only leverages contributor_log instead of contributor_shortlog
  def counts_by_author_log
    return {} unless repository.default_oid

    repository.rpc.contributor_log(repository.default_oid,
      ignore_merge_commits: ignore_merge_commits,
      mailmap: mailmap,
    )
  end

  # Fetch the git-shortlog for the repository including contribution counts,
  # Git author, and email address.
  #
  # Returns a log as a String in format of:
  #
  #  1365  Jared Pace <jared@example.com>
  #  1310  Jason Long <jlong@example.com>
  #  1269  Mu-An Chiou <megaemoji@example.com>
  def shortlog
    raise UncomputableShortlog if shortlog_not_computable?
    return "" unless repository.default_oid

    GitHub.cache.fetch(shortlog_cache_key, ttl: 1.hour) do
      GitHub.instrument("repository.fetch_contributors") do
        repository.rpc.contributor_shortlog(repository.default_oid, ignore_merge_commits: ignore_merge_commits)
      end
    end
  end
end
