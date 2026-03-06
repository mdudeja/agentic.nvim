import type { NewSessionResponse } from '@agentclientprotocol/sdk'
import type { Message, SessionSummary } from 'src/database/schemas'
import type { ASMState } from 'src/state/IASMState'

export type AgentEvents = {
  'agent.created': ASMState['agent']
  'agent.loaded': ASMState['agent']
  'agent.spawned': ASMState['agent']
  'agent.killed': ASMState['agent']
  'agent.connected': ASMState['agent']
  'agent.disconnected': ASMState['agent']
  'agent.error': string
}

export type AgentEventNames = keyof AgentEvents

export type SessionEvents = {
  'session.acp_created': NewSessionResponse
  'session.created': ASMState['session']
  'session.updated': ASMState['session']
  'session.loaded': ASMState['session']
  'session.error': string
  'session.renamed': ASMState['session']
  'session.completed': ASMState['session']
  'session.deleted': string
}

export type SessionEventNames = keyof SessionEvents

export type SummaryEvents = {
  'summary.created': SessionSummary['Select']
  'summary.updated': SessionSummary['Select']
  'summary.deleted': string
  'summary.error': string
}

export type SummaryEventNames = keyof SummaryEvents

export type MessageEvents = {
  'message.manager_init': void
  'message.prompted': Message['Select']
  'message.responded': Message['Select']
  'message.error': string
}
