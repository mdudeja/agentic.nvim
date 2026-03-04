import type { ASMState, IASMState } from './IASMState'

export class ASMStateManager implements IASMState {
  private state: ASMState = {}

  setItem(key: keyof ASMState, value: any): void {
    this.state[key] = value
  }

  updateItem(key: keyof ASMState, value: any): void {
    if (this.state[key]) {
      this.state[key] = { ...this.state[key], ...value }
    } else {
      this.state[key] = value
    }
  }

  deleteItem(key: keyof ASMState): void {
    delete this.state[key]
  }

  getItem(key: keyof ASMState) {
    return this.state[key]
  }

  getState(): ASMState {
    return this.state
  }

  dispose() {
    this.state = {}
  }
}
