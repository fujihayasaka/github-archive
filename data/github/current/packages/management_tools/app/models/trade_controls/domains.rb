# typed: strict
# frozen_string_literal: true

require "set"

module TradeControls
  # Represents a collection of sanctioned domain instances.
  class Domains

    RU_SANCTIONED_DOMAINS = T.let(%w(
      3d.ru
      3data.ru
      5dtech.pro
      75arsenal.ru
      abamet.ru
      abank.ru
      absolutbank.ru
      abuniversal.ru
      acuta.ru
      aerospace-systems.ru
      agrisovgaz.ru
      agroros.ru
      air-burg.ru
      akbars.ru
      akcept.ru
      akibank.ru
      aktiv.ru
      alabuga.ru
      alexbank.ru
      alfabank.ru
      alfaleasing.ru
      alhazmiex.com
      allrus.ru
      almaz.ru
      alrosa.ru
      amelkin.msk.ru
      amstehnika.ru
      amz.ru
      ankb.ru
      anodialog.ru
      ao-star.ru
      aoafs.ru
      aomrk.ru
      aq.ru
      aramid.ru
      arcticspg.ru
      argus-sfk.ru
      ase-ec.ru
      astracom.ru
      astralinux.ru
      atmt.ru
      autofinancebank.ru
      avangard.ru
      avtodor-tr.ru
      axion.ru
      aziaship.ru
      azimp.ru
      azsco.ru
      baikalelectronics.ru
      baltinfocom.ru
      bank-hlynov.ru
      bank.bcs.ru
      bankorange.ru
      bazissoft.ru
      bbr.ru
      bitvan.ru
      bki-okb.ru
      blanc.ru
      boldrex.ru
      bspb.ru
      bystrobank.ru
      ca-group.ru
      casestudio.ru
      cbr.ru
      ccb.ru
      cetelem.ru
      cfb.ru
      chelindbank.ru
      chkpz.ru
      chtpz.tmk-group.ru
      ciam.ru
      ckb-rubin.ru
      cnirti.ru
      coalmetbank.ru
      compel.ru
      compressormash.ru
      cryogenmash.ru
      cscled.ru
      cvetmir3d.ru
      datana.ru
      depoplaza.ru
      depository.ru
      depotech.ru
      derzhava.ru
      dialog-regions.ru
      digispace.ru
      dmzdubna.ru
      domrfbank.ru
      dsol.ru
      durma.ru
      e-moskva.ru
      e-streloy.ru
      ekos-1.ru
      elins.ru
      elpapiezo.ru
      en.16k20.ru
      energobank.ru
      epkgroup.ru
      eposignal.ru
      erdc.ru
      esphere.ru
      etbank.ru
      exibank.ru
      expobank.ru
      exportcenter.ru
      fedorovoresources.ru
      fgup-ohrana.ru
      finsb.ru
      fkpppz.ru
      forabank.ru
      frsd.ru
      frtk.ru
      gardatech.ru
      gazprom-auto.ru
      gazprom-neft.ru
      gazprom-spacesystems.ru
      gazprombank.ru
      gibank.ru
      gidroagregat-nn.ru
      gle.ru
      goi.ru
      gribnaya-raduga.ru
      gstou.ru
      gtsgrup.ru
      gubkin.ru
      gutabank.ru
      gvgold.ru
      homecredit.ru
      hydromash.ru
      icl.ru
      ih.rosatom.ru
      in-vent.ru
      infcs.ru
      innodrive.ru
      investstanok.ru
      ioffe.ru
      ipfran.ru
      irkutskkabel.ru
      iss-reshetnev.ru
      issp.ac.ru
      iteranet.ru
      iturupbank.ru
      ivfrt.ru
      izhcombank.ru
      jetcom.ru
      juventalaser.ru
      k-soft-spb.ru
      kamkombank.ru
      kcdt.ru
      keldysh.ru
      kemz.org
      knc.ru
      komponenta.ru
      kraftway.ru
      kremlinbank.ru
      krona-bank.ru
      kronshtadt.ru
      krug2000.ru
      kryptonite.ru
      kupol.ru
      kzgroup.ru
      laggar-pro.ru
      laspace.ru
      lebedev.ru
      lit-phonon.ru
      lobaevfond.ru
      lockobank.ru
      logfortra.ru
      lsystems.ru
      lveplant.ru
      macroems.ru
      macrooptica.ru
      mage.ru
      mcst.ru
      mechel.ru
      melytec.ru
      metallurgbank.ru
      metalmaster.ru
      metcom.ru
      mfisoft.ru
      mfk-bank.ru
      mgri.ru
      milandr.ru
      milindcom.ru
      miran.ru
      mkb.ru
      mks-group.ru
      mmzavod.ru
      mnsspb.ru
      modulbank.ru
      module.ru
      mosinzhproekt.ru
      motor-invest.ru
      mpei.ru
      mrb-bank.ru
      mts.ru
      mtsbank.ru
      nami.ru
      ndb24.ru
      newreg.ru
      newtowers.ru
      niiet.ru
      niihit.ru
      niitm.spb.ru
      niitp.ru
      nipigas.ru
      nissadistribution.ru
      niti.ru
      nkbank.ru
      nkk-sd.ru
      nmbank.ru
      nmz-iskra.ru
      nmz.ru
      norsi-trans.ru
      novatek.ru
      npcap.ru
      npo-comp.ru
      npoelm.ru
      npp-istochnik.ru
      npp-radiy.ru
      nppgamma.ru
      nrb.ru
      nrcreg.ru
      ns-bank.ru
      nsbank.ru
      nskbl.ru
      nspcc.ru
      nspk.ru
      nvs-gnss.ru
      nzl.ru
      nzsd.ru
      nzsip.ru
      nzslp.ru
      ocean.ru
      okb-sokol.ru
      okbank.ru
      oksibalt.ru
      oktanta-ndt.ru
      oleokam.ru
      omk.ru
      ooo-monitoring.ru
      open.ru
      optron-stavropol.ru
      osnovalab.ru
      ostec-group.ru
      pgups.ru
      phcloud.ru
      picaso-3d.ru
      pochtabank.ru
      podolskkabel.ru
      priusel.ru
      proletarsky.ru
      promreshenie.ru
      promtech-dubna.ru
      promtech-kazan.ru
      prosoft.ru
      psbank.ru
      pscb.ru
      ptkb.ru
      ptkgroup.ru
      ptsecurity.ru
      pzmc.org
      quanttelecom.ru
      quick-cnc.ru
      quorum.ru
      radioavionica.ru
      rawenstvo.ru
      rdb.ru
      realexport.ru
      realloc.spb.ru
      red-soft.ru
      reggarant.ru
      resource-soft.ru
      rifcorp.ru
      rimera.ru
      rirt.ru
      rnt.ru
      rosatom.ru
      rosbank.ru
      rostfinance.ru
      round.ru
      royal-bank.ru
      rq.ru
      rqc.ru
      rsb.ru
      rshb.ru
      rt.ru
      rubank.ru
      rusbitech.ru
      rusgeology.ru
      rushydro.ru
      russitabank.ru
      rusventure.ru
      rutarget.ru
      rvc.ru
      s7technics.ru
      sber-solutions.ru
      sberbank-ast.ru
      sberbank-cib.ru
      sberbank.ru
      sbercloud.ru
      scanform.ru
      sdkgarant.ru
      securitycode.ru
      severgazbank.ru
      sfinks-sl.ru
      shipyard-yantar.ru
      shtormtech.ru
      siab.ru
      signal-teplo.ru
      signaltec.ru
      signatec.ru
      sinara.ru
      sintz.tmk-group.ru
      sistema.ru
      siusystem.ru
      skolkovo.ru
      skolkovotech.ru
      skoltech.ru
      skzi.ru
      slaviabank.ru
      smartlogister.ru
      sogaz.ru
      sonis-co.ru
      sovcombank.ru
      sovrudnik.ru
      spacecorp.ru
      spbexchange.ru
      specdep.ru
      spectrumit.ru
      sphotonics.ru
      sprut.ru
      ssep.ru
      sskzvezda.ru
      stanki.ru
      steerer.ru
      sts-trans.ru
      stz.tmk-group.ru
      suek.ru
      sverdlova.ru
      svpz.ru
      symmetron.ru
      systempb.ru
      t-argos.ru
      t1.ru
      tagmet.tmk-group.ru
      tbss.ru
      temp-avia.ru
      tetis-pro.ru
      tflex.ru
      timerbank.ru
      tinkoff.ru
      tkbbank.ru
      tmholding.ru
      tmk-group.ru
      top3dgroup.ru
      totalz.ru
      touchin.ru
      trcont.ru
      tribit.ru
      trust.ru
      trustinfo.ru
      tulamash.ru
      tulammo.ru
      tulatochmash.ru
      tulatoz.ru
      tvema.ru
      tverna.ru
      u-mac.ru
      ubrr.ru
      umpo.ru
      united.ru
      uralfd.ru
      uralmash-kartex.ru
      uralsib.ru
      vbf.ru
      velobike.ru
      vende-group.com
      vestabank.ru
      vikingbank.ru
      vitabank.ru
      vniia.ru
      vniief.ru
      vostokwatch.ru
      vscport.ru
      vtb.ru
      vtz.tmk-group.ru
      vympel.ru
      vzavod.ru
      wagnercentr.ru
      waybank.ru
      weber.ru
      yarz.ru
      yoomoney.ru
      z-axis.ru
      zavod-elecon.ru
      zenit.ru
      zenit3d.ru
      zid.ru
    ).freeze, T::Array[String])

    UA_SANCTIONED_DOMAINS = T.let(%w(
      pib.ua
      sbrf.com.ua
    ).freeze, T::Array[String])

    FI_SANCTIONED_DOMAINS = T.let(%w(
      hd-parts.fi
    ).freeze, T::Array[String])

    KZ_SANCTIONED_DOMAINS = T.let(%w(
      da-group22.kz
    ).freeze, T::Array[String])

    BY_SANCTIONED_DOMAINS = T.let(%w(
      agat.by
      amkodor.by
      avia407.by
      bankdabrabyt.by
      belavia.by
      belveb.by
      intechs.by
      kbradar.by
      mzkt.by
      uavheli.by
    ).freeze, T::Array[String])

    SY_SANCTIONED_DOMAINS = T.let(%w(
      dz-water.gov.sy
      hiast.edu.sy
      tishreen.edu.sy
    ).freeze, T::Array[String])

    AT_SANCTIONED_DOMAINS = T.let(%w(
      sberbank.at
    ).freeze, T::Array[String])

    EU_SANCTIONED_DOMAINS = T.let(%w(
      vtb.eu
    ).freeze, T::Array[String])

    VN_SANCTIONED_DOMAINS = T.let(%w(
      vtb.com.vn
    ).freeze, T::Array[String])

    TR_SANCTIONED_DOMAINS = T.let(%w(
      asbgroup.com.tr
      bosfor-avrasya.com.tr
      egetir.com.tr
      globusturkey.com.tr
      sistema.com.tr
      mbk-paz-san.com.tr
    ).freeze, T::Array[String])

    SU_SANCTIONED_DOMAINS = T.let(%w(
      bodor.su
      evrazia.su
      inp.nsk.su
      novak.su
      quarta.su
      vpv.su
    ).freeze, T::Array[String])

    DE_SANCTIONED_DOMAINS = T.let(%w(
      bentway.de
      kara-trading.de
    ).freeze, T::Array[String])

    ME_SANCTIONED_DOMAINS = T.let(%w(
      ideascup.me
    ).freeze, T::Array[String])

    AE_SANCTIONED_DOMAINS = T.let(%w(
      hamriyahsteel.ae
      igsm.ae
      jaziradas-intl.ae
      ldscomtrade.ae
      skyparts.ae
    ).freeze, T::Array[String])

    IN_SANCTIONED_DOMAINS = T.let(%w(
      ron.in
    ).freeze, T::Array[String])

    RS_SANCTIONED_DOMAINS = T.let(%w(
      mci.rs
      kominvex.co.rs
      tr-industries.rs
      sohainfo.rs
    ).freeze, T::Array[String])

    MV_SANCTIONED_DOMAINS = T.let(%w(
      vbbrothers.com.mv
    ).freeze, T::Array[String])

    CN_SANCTIONED_DOMAINS = T.let(%w(
      gt.cn
      jl1.cn
      limbach.cn
      rdscargo.ae.cn
      riamb.ac.cn
    ).freeze, T::Array[String])

    RO_SANCTIONED_DOMAINS = T.let(%w(
      sistema.com.ro
    ).freeze, T::Array[String])

    BA_SANCTIONED_DOMAINS = T.let(%w(
      prointer.ba
      sirius2010.ba
    ).freeze, T::Array[String])

    BE_SANCTIONED_DOMAINS = T.let(%w(
      ett.be
    ).freeze, T::Array[String])

    PS_SANCTIONED_DOMAINS = T.let(%w(
      herzallah.ps
    ).freeze, T::Array[String])

    CH_SANCTIONED_DOMAINS = T.let(%w(
      thamestone.ch
      gazprombank.ch
    ).freeze, T::Array[String])

    KG_SANCTIONED_DOMAINS = T.let(%w(
      weitmann.kg
    ).freeze, T::Array[String])

    SG_SANCTIONED_DOMAINS = T.let(%w(
      microetech.sg
    ).freeze, T::Array[String])

    OTHER_SANCTIONED_DOMAINS = T.let(%w(
      acs-lc.com
      aithea.com
      alfabank.com
      ali2k.com
      aliabkar.com
      alphaforeign.com
      archlinux.us
      arttronix.com
      arvancloud.com
      arxfe.com
      auriga.com
      avrorasystems.com
      baikalelectronics.com
      baspik.com
      beepitron.com
      bigmir.net
      burevestnik.com
      cady-ic.com
      cae-fidesys.com
      chinele.com
      chista.io
      corebai.com
      crc-reg.com
      crynofistaviation.com
      cryptex.net
      cubitsemi.com
      deeppavlov.ai
      develoop.run
      dialog.info
      digikala.com
      digitalenergy.online
      dimkt.net
      ecomaxtrade.com
      elbcp.com
      eledtrodetal.com
      elektrodetal.com
      elix-st.com
      en.ownlon.com
      energotransbank.com
      etanofuel.com
      farzambehboudi.com
      farzaneganpb.com
      futurisfze.com
      galileosmarine.com
      gardencityhotel.com.kh
      gazprombank.lu
      gclogistics-me.com
      geoscan.aero
      gmfarmco.com
      gpbame.com
      gpbfs.com.cy
      greatsharelogistics.com
      gruzinov.com
      gsk-sd.com
      hasani.com
      hiflb.com
      highlandgold.com
      hodico.com
      isbnk.org
      itbrk.com
      itc-electronics.com
      jarvisint.com
      jhcircuits.com
      jsc-energiya.com
      jxlszb.com
      kartal-exim.com
      kismetcg.com
      kohkongresort.com
      kompaniets.dev
      kraden.com
      light-shipmanagement.com
      linker.aero
      lithium-element.com
      loqusgroup.com
      lypgroup.com
      maiwe.com.cn
      maritimebank.com
      megasan.com
      merkurenergyports.com
      mirageaircraftservices.com
      morphbits.io
      mousavi.info
      multiclet.com
      navis-elektronika.com
      nexign.com
      npoakonit.com
      npzoptics.com
      oaoapz.com
      olimpikgama.com
      ozkayaotomotiv.net
      partners.rt.com
      peppersec.com
      phnompenhhotel.com
      pik-group.com
      polarstar.ae
      polimerprom.com
      polyus.com
      precious-bullion.com
      presstv.com
      proheli.net
      prom-ts.com
      promoil.com
      pskb.com
      ptsecurity.com
      pullman.solutions
      pumaenergy.com
      pumori.com
      qubit.org
      radiocomp.net
      researchgroupnederland.com
      resolute-mt.com
      rhc.aero
      rimera.com
      rose-shipping.gr
      rossiyasegodnya.com
      ruhmeerdiamonds.com
      rusatom-cargo.com
      rusavtomatika.com
      russian.rt.com
      salinaships.com
      samara-metallurg.ru
      scf-group.com
      sciprog.center
      sharif.edu
      shengcore-ic.com
      sinocnc.com
      skyda.co
      smng.com
      sovtest-ate.com
      stankomach.com
      status-it.com
      suek.com
      sunmultinational.com
      sunstartravels.com
      suzangen.com
      svyazservis.com
      swisstecag.com
      tefcas.com.my
      tensy.org
      tgr.company
      tgr.partners
      tornado.cash
      trcont.com
      triangulatica.com
      turkikunion.com
      ubank.net
      ugmk.com
      umatex.com
      uniguajira.edu.co
      uralhelicom.com
      uralmash-ngo.com
      uu-ic.com
      velesstroy.com
      visionshipmanagement.com
      vremya-ch.com
      vtb.com
      vygon.consulting
      yadro.com
      ylfelectronics.com
      zadna-int.com
      zargeo.com
      zrenergy.com
    ).freeze, T::Array[String])

    IR_SANCTIONED_DOMAINS = T.let(%w(
      agri-jahad.ir
      aliabkar.ir
      amnafzar.ir
      aut.ac.ir
      bahman.ir
      comp.iust.ac.ir
      email.kntu.ac.ir
      iran.ir
      isc.co.ir
      justice.ir
      mail.sbu.ac.ir
      mcth.ir
      medu.ir
      mod.ir
      modi.ir
      moi.ir
      mop.ir
      mrud.ir
      msrt.ir
      mut.ac.ir
      peykasa.ir
      peymanmajidi.ir
      rezamk.ir
      sahab.ir
      sbu.ac.ir
      ut.ac.ir
      vaja.ir
    ).freeze, T::Array[String])

    CU_SANCTIONED_DOMAINS = T.let(%w(
      agrinfor.cu
      avianet.cu
      ceniai.inf.cu
      cubadefensa.cu
      fishnavy.inf.cu
      hidro.cu
      infomed.sld.cu
      mfp.gov.cu
      mic.cu
      micons.cu
      min.cult.cu
      minint.gob.cu
      minjus.cu
      minrex.gob.cu
      parlamentocubano.gob.cu
      reduniv.edu.cu
      sime.co.cu
      tsp.gob.cu
    ).freeze, T::Array[String])

    IR_SANCTIONED_TLDS = T.let(%w(
      .gov.ir
    ).freeze, T::Array[String])

    CU_SANCTIONED_TLDS = T.let(%w(
      .gob.cu
    ).freeze, T::Array[String])

    SANCTIONED_DOMAINS = T.let(
      []
        .concat(AE_SANCTIONED_DOMAINS)
        .concat(AT_SANCTIONED_DOMAINS)
        .concat(BA_SANCTIONED_DOMAINS)
        .concat(BE_SANCTIONED_DOMAINS)
        .concat(BY_SANCTIONED_DOMAINS)
        .concat(CH_SANCTIONED_DOMAINS)
        .concat(CN_SANCTIONED_DOMAINS)
        .concat(CU_SANCTIONED_DOMAINS)
        .concat(DE_SANCTIONED_DOMAINS)
        .concat(EU_SANCTIONED_DOMAINS)
        .concat(FI_SANCTIONED_DOMAINS)
        .concat(IN_SANCTIONED_DOMAINS)
        .concat(IR_SANCTIONED_DOMAINS)
        .concat(KG_SANCTIONED_DOMAINS)
        .concat(KZ_SANCTIONED_DOMAINS)
        .concat(ME_SANCTIONED_DOMAINS)
        .concat(MV_SANCTIONED_DOMAINS)
        .concat(OTHER_SANCTIONED_DOMAINS)
        .concat(PS_SANCTIONED_DOMAINS)
        .concat(RO_SANCTIONED_DOMAINS)
        .concat(RS_SANCTIONED_DOMAINS)
        .concat(RU_SANCTIONED_DOMAINS)
        .concat(SG_SANCTIONED_DOMAINS)
        .concat(SU_SANCTIONED_DOMAINS)
        .concat(SY_SANCTIONED_DOMAINS)
        .concat(TR_SANCTIONED_DOMAINS)
        .concat(UA_SANCTIONED_DOMAINS)
        .concat(VN_SANCTIONED_DOMAINS)
        .to_set.freeze, T::Set[String]
    )
    SANCTIONED_TLDS = T.let([].concat(IR_SANCTIONED_TLDS).concat(CU_SANCTIONED_TLDS).to_set.freeze, T::Set[String])

    sig { params(email: T.nilable(String)).returns(T::Boolean) }
    def self.sanctioned_email?(email)
      # organizations isn't required to set billing_emails, and as such email can be nil
      return false if email.blank?

      downcased_domain = email.split("@").last.to_s.strip.downcase
      return false if downcased_domain.blank?

      return true if SANCTIONED_DOMAINS.include?(downcased_domain)

      SANCTIONED_TLDS.any? { |d| downcased_domain.end_with?(d) }
    end
  end
end
