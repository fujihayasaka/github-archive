import {Heading, Link, TextInput} from '@primer/react'

import styles from './TotalSeats.module.css'

type TotalSeatsProps = {
  seats: number
  setSeats: (seats: number) => void
}

function TotalSeats({seats, setSeats}: TotalSeatsProps) {
  return (
    <div className={styles.Box}>
      <Heading as="h2" className={styles.Heading}>
        Total seats
      </Heading>
      <div className={styles.Box_1}>
        <div className={styles.Box_2}>
          <div className={styles.Box_3}>
            <TextInput
              type="number"
              min={1}
              id="seats"
              value={seats}
              onChange={e => setSeats(Number(e.target.value))}
              defaultValue={12}
            />
            <label htmlFor="seats" className={styles.Text}>
              seats
            </label>
          </div>
          <span className={styles.Text_1}>
            Your organization is currently using 1 seat.{' '}
            <Link href="https://github.com" inline>
              Manage seats
            </Link>
          </span>
        </div>
      </div>
    </div>
  )
}

export default TotalSeats
