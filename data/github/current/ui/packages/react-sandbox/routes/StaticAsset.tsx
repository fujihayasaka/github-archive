import monaHeart from '../assets/mona-heart.gif'

export function StaticAsset() {
  const logo = <img elementtiming="mona-heart-logo" id="this-is-a-test" src={monaHeart} alt="" />
  return <div data-hpc>{logo}</div>
}
