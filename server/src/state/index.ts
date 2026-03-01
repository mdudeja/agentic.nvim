import type { Subprocess } from 'bun'
import type { Agent, Session } from 'src/database/schemas'

export interface ASMState {
  agent: Agent['Select'] & {
    process?: Subprocess
  }
  session?: Session['Select']
}

const state: ASMState = {} as ASMState

export function setStateItem<K extends keyof ASMState>(
  key: K,
  value: ASMState[K],
) {
  state[key] = value
}

export function getStateItem<K extends keyof ASMState>(
  key: K,
): ASMState[K] | undefined {
  return state[key]
}

export function updateStateItem<K extends keyof ASMState>(
  key: K,
  value: Partial<ASMState[K]>,
) {
  if (!state[key]) {
    state[key] = value as ASMState[K]
  } else {
    state[key] = { ...state[key], ...value }
  }
}

export function getState() {
  return state
}
