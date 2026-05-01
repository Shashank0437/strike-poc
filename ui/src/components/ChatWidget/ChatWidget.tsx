import { useState, useEffect, useRef } from 'react'
import { MessageSquare, ChevronLeft, ChevronRight, ArrowDown } from 'lucide-react'
import { ChatSidebar } from './ChatSidebar'
import { ChatMessageList } from './ChatMessageList'
import { ChatInput } from './ChatInput'
import { useChatSessions } from './useChatSessions'
import { useChatStream } from './useChatStream'
import type { ChatMessage } from './useChatStream'
import './ChatWidget.css'

const OPEN_KEY = 'nyxstrike_chat_open'

function loadOpen(): boolean {
  try { return localStorage.getItem(OPEN_KEY) === '1' } catch { return false }
}
function saveOpen(v: boolean) {
  try { localStorage.setItem(OPEN_KEY, v ? '1' : '0') } catch {}
}

interface ChatWidgetProps {
  llmAvailable: boolean
  currentPage: string
  currentSessionId: string | null
}

export function ChatWidget({ llmAvailable, currentPage, currentSessionId }: ChatWidgetProps) {
  const [open, setOpen] = useState(loadOpen)
  const [sidebarOpen, setSidebarOpen] = useState(true)
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null)
  const [prefill, setPrefill] = useState<string>('')

  const { sessions, loading, createSession, deleteSession, deleteAllSessions, updateSessionName, renameSession } = useChatSessions()
  const { messages, streaming, send, stop, loadHistory, clearMessages, confirmToolCall } = useChatStream(activeSessionId)

  const widgetRef = useRef<HTMLDivElement>(null)
  const autoCreatedRef = useRef(false)

  // Keyboard shortcut Ctrl+Shift+C
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.ctrlKey && e.shiftKey && e.key.toLowerCase() === 'c') {
        e.preventDefault()
        setOpen(prev => {
          saveOpen(!prev)
          return !prev
        })
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  // Auto-select most recent session, or create one if none exist
  useEffect(() => {
    if (loading) return
    if (!activeSessionId && sessions.length > 0) {
      setActiveSessionId(sessions[0].id)
    } else if (!activeSessionId && sessions.length === 0 && !autoCreatedRef.current) {
      autoCreatedRef.current = true
      handleCreateSession()
    }
  }, [sessions, activeSessionId, loading]) // eslint-disable-line react-hooks/exhaustive-deps

  // Load history when session changes
  useEffect(() => {
    if (activeSessionId) {
      clearMessages()
      loadHistory(activeSessionId)
    }
  }, [activeSessionId]) // eslint-disable-line react-hooks/exhaustive-deps

  async function handleCreateSession() {
    const sess = await createSession()
    if (sess) {
      setActiveSessionId(sess.id)
      clearMessages()
    } else {
      autoCreatedRef.current = false
    }
  }

  async function handleDeleteSession(id: string) {
    await deleteSession(id)
    if (activeSessionId === id) {
      const remaining = sessions.filter(s => s.id !== id)
      if (remaining.length > 0) {
        setActiveSessionId(remaining[0].id)
      } else {
        setActiveSessionId(null)
        clearMessages()
      }
    }
  }

  async function handleDeleteAllSessions() {
    await deleteAllSessions()
    setActiveSessionId(null)
    clearMessages()
  }

  function handleSend(text: string) {
    if (!activeSessionId) return
    const ctx = { page: currentPage, session_id: currentSessionId || '' }
    // Auto-name session from first message
    const active = sessions.find(s => s.id === activeSessionId)
    if (active && !active.name) {
      updateSessionName(activeSessionId, text.slice(0, 50))
    }
    send(text, ctx)
  }

  function handleRetry(msg: ChatMessage) {
    // Find the user message just before this error
    const idx = messages.indexOf(msg)
    if (idx > 0 && messages[idx - 1].role === 'user') {
      const original = messages[idx - 1].content
      const ctx = { page: currentPage, session_id: currentSessionId || '' }
      send(original, ctx)
    }
  }


  function toggleOpen() {
    setOpen(prev => { saveOpen(!prev); return !prev })
  }

  if (!llmAvailable) return null

  const activeSession = sessions.find(s => s.id === activeSessionId)
  const sessionLabel = activeSession?.name || (activeSessionId ? 'New chat' : 'Starting…')

  return (
    <>
      {/* FAB */}
      {!open && (
        <button
          className="chat-fab"
          onClick={toggleOpen}
          title="Open AI Assistant (Ctrl+Shift+C)"
          aria-label="Open NyxStrike AI Assistant"
        >
          <MessageSquare />
        </button>
      )}

      {/* Widget */}
      {open && (
        <div ref={widgetRef} className="chat-widget">

          <div className="chat-layout">
            {/* Sidebar */}
            {sidebarOpen && (
              <ChatSidebar
                sessions={sessions}
                activeSessionId={activeSessionId}
                onSelectSession={id => { setActiveSessionId(id) }}
                onCreateSession={handleCreateSession}
                onDeleteSession={handleDeleteSession}
                onDeleteAllSessions={handleDeleteAllSessions}
                onRenameSession={renameSession}
              />
            )}

            {/* Main panel */}
            <div className="chat-main">
              {/* Header */}
              <div className="chat-header">
                <button
                  className="chat-sidebar-toggle"
                  onClick={() => setSidebarOpen(prev => !prev)}
                  title={sidebarOpen ? 'Hide sessions' : 'Show sessions'}
                >
                  {sidebarOpen ? <ChevronLeft size={14} /> : <ChevronRight size={14} />}
                </button>
                <div className="chat-header-info">
                  <span className="chat-header-title">NyxStrike AI</span>
                  {currentSessionId && currentPage === 'session-detail' && (
                    <span className="chat-context-badge">context: session</span>
                  )}
                  <span className="chat-session-label mono">{sessionLabel}</span>
                </div>
                <button className="chat-close-btn" onClick={toggleOpen} title="Close chat (Ctrl+Shift+C)">
                  <ArrowDown size={16} />
                </button>
              </div>

              {/* Messages */}
              <ChatMessageList
                messages={messages}
                onRetry={handleRetry}
                onConfirmTool={confirmToolCall}
                onSuggest={setPrefill}
              />

              {/* Input wrapper for centering */}
              <div className="chat-input-wrapper">
                <ChatInput
                  onSend={handleSend}
                  streaming={streaming}
                  onStop={stop}
                  disabled={!activeSessionId}
                  prefill={prefill}
                />
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
