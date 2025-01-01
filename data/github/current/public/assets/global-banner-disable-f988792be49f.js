const dgsbMatches = document.cookie.match(new RegExp(`(?:^|;\\s*)disabled_global_site_banners\\s*=\\s*([^;]+)`));
const dgsbCookie = dgsbMatches ? dgsbMatches[1] : null;
if (dgsbCookie) {
  const dgsbBanners = dgsbCookie.split(',') || [];
  for (let i = 0; i < dgsbBanners.length; i++) {
    const banner = document.getElementById(dgsbBanners[i] || '');
    if (banner) banner.hidden = true;
  }
}
