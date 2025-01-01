import type {Path} from 'd3'

class Step {
  private _context: CanvasRenderingContext2D | Path
  private _t: number
  private _radius: number
  private _line: number
  private _x: number
  private _y: number
  private _point: number

  constructor(context: CanvasRenderingContext2D | Path, t: number, radius: number) {
    this._context = context
    this._t = t
    this._radius = radius
    this._line = 0
    this._x = NaN
    this._y = NaN
    this._point = 0
  }

  areaStart(): void {
    this._line = 0
  }

  areaEnd(): void {
    this._line = NaN
  }

  lineStart(): void {
    this._x = NaN
    this._y = NaN
    this._point = 0
  }

  lineEnd(): void {
    if (this._t > 0 && this._t < 1 && this._point === 2) {
      this._context.lineTo(this._x, this._y)
    }
    if (this._line || (this._line !== 0 && this._point === 1)) {
      this._context.closePath()
    }
    if (this._line >= 0) {
      this._t = 1 - this._t
      this._line = 1 - this._line
    }
  }

  point(x_: number, y_: number): void {
    const x = +x_
    const y = +y_

    switch (this._point) {
      case 0:
        this._point = 1
        if (this._line) {
          this._context.lineTo(x, y)
        } else {
          this._context.moveTo(x, y)
        }
        break
      case 1:
        this._point = 2
      // falls through intentionally to default case
      default: {
        let x1: number
        let y1: number
        if (this._t <= 0) {
          this._context.arcTo(this._x, y, this._x - this._radius, y, this._radius)
          this._context.lineTo(x, y)
        } else {
          // Intermediate inference between previous and current point
          x1 = this._x * (1 - this._t) + x * this._t
          y1 = this._y * (1 - this._t) + y * this._t

          // Check angle to determine arc direction
          if (this._y < y - this._radius) {
            // Top to Bottom Arc
            this._context.arcTo(this._x, this._y, x, y1, this._radius)
          } else if (this._y > y + this._radius) {
            // Bottom to Top Arc
            this._context.arcTo(this._x, this._y, x, y1, this._radius)
          } else if (this._x < x - this._radius) {
            // Left to Right Arc
            this._context.arcTo(this._x, this._y, x1, y, this._radius)
          } else if (this._x > x + this._radius) {
            // Right to Left Arc
            this._context.arcTo(this._x, this._y, x1, y, this._radius)
          } else {
            // Fallback to a straight line
            this._context.lineTo(x, y)
          }
        }
        break
      }
    }
    this._x = x
    this._y = y
  }
}

export const stepRound = (context: CanvasRenderingContext2D | Path, radius: number): Step => {
  return new Step(context, 0.5, radius)
}
