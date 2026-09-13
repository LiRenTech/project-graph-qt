import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/progress";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { Project } from "@/core/Project";
import {
  AIChatSessionStore,
  type AIChatSessionProjectState,
  type AIChatSessionSummary,
  type StoredAIChatSession,
} from "@/core/service/dataManageService/aiEngine/AIChatSessionStore";
import type { AIMessageMetadata } from "@/core/service/dataManageService/aiEngine/AIEngine";
import {
  resolveAIModelContextWindow,
  type AIModelContextWindow,
} from "@/core/service/dataManageService/aiEngine/AIModelContextWindow";
import { AIObjectReferenceRegistry } from "@/core/service/dataManageService/aiEngine/AIObjectReferenceRegistry";
import { AIProjectReferenceStore } from "@/core/service/dataManageService/aiEngine/AIProjectReferenceStore";
import { getAIToolPartName, isAIToolPart } from "@/core/service/dataManageService/aiEngine/AIToolUIPart";
import { Settings } from "@/core/service/Settings";
import { ConnectableEntity } from "@/core/stage/stageObject/abstract/ConnectableEntity";
import { CollisionBox } from "@/core/stage/stageObject/collisionBox/collisionBox";
import { Section } from "@/core/stage/stageObject/entity/Section";
import { TextNode } from "@/core/stage/stageObject/entity/TextNode";
import { createSubWindow } from "@/core/subWindowOpen";
import { TabWorkspace } from "@/core/TabWorkspace";
import { activeResourceTabAtom } from "@/state";
import { cn } from "@/utils/cn";
import { AIRequestTraceView } from "@/sub/AIRequestTraceView";
import { useChat } from "@ai-sdk/react";
import { Color, Vector } from "@graphif/data-structures";
import { Rectangle } from "@graphif/shapes";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@radix-ui/react-collapsible";
import { code } from "@streamdown/code";
import { lastAssistantMessageIsCompleteWithApprovalResponses, type UIMessage } from "ai";
import { useAtom } from "jotai";
import {
  Bot,
  Check,
  ChevronRight,
  FolderOpen,
  History,
  MoreHorizontal,
  Paperclip,
  Pencil,
  Plus,
  Send,
  ShieldCheck,
  Sparkles,
  Square,
  Trash2,
  User,
  X,
} from "lucide-react";
import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { Streamdown } from "streamdown";
import "streamdown/styles.css";
import { getOriginalNameOf } from "virtual:original-class-name";

let pendingInitialText: string | null = null;
let pendingInitialPrompt: string | null = null;

export function setAIWindowInitialText(text: string, prompt?: string) {
  pendingInitialText = text;
  pendingInitialPrompt = prompt || null;
}

export default function AIWindow({ tabId }: { tabId: string }) {
  const [tab] = useAtom(activeResourceTabAtom);
  const project = tab instanceof Project ? tab : undefined;

  if (!project) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-3 p-8 text-center">
        <FolderOpen className="text-muted-foreground size-10" />
        <div className="font-medium">请先打开一个文件</div>
        <div className="text-muted-foreground max-w-64 text-sm">
          AI 工具需要当前画布上下文，打开文件后就可以帮你创建、整理和修改节点。
        </div>
      </div>
    );
  }

  return <AIChatWorkspace key={project.uri.toString()} project={project} tabId={tabId} />;
}

function getContrastTextColor(bg: Color): string {
  const luminance = (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b) / 255;
  return luminance > 0.6 ? "#000" : "#fff";
}

function isEntity(
  obj: unknown,
): obj is { isSelected: boolean; collisionBox: { getRectangle(): Rectangle }; color?: Color } {
  return typeof obj === "object" && obj !== null && "isSelected" in obj && "collisionBox" in obj;
}

type ContextWindowState =
  | { status: "loading" }
  | { status: "ready"; info: AIModelContextWindow }
  | { status: "unknown" }
  | { status: "error"; message: string };

function createAnswerNode(message: UIMessage, project: Project) {
  const answerText = (Array.isArray(message.parts) ? message.parts : [])
    .filter((p: any) => p.type === "text")
    .map((p: any) => p.text ?? "")
    .join("\n")
    .trim();
  if (!answerText) {
    toast.error("该消息没有可落盘的文本");
    return;
  }
  const selected = project.stageManager.getSelectedEntities();
  const source = selected.find((e) => e instanceof Section) ?? selected.find((e) => e instanceof ConnectableEntity);
  if (!source) {
    toast.error("请先选中要指向的分组框或节点");
    return;
  }
  const sourceRect = source.collisionBox.getRectangle();
  const node = new TextNode(project, {
    text: answerText,
    color: new Color(0, 0, 0, 0),
    collisionBox: new CollisionBox([
      new Rectangle(
        new Vector(sourceRect.location.x + sourceRect.size.x + 100, sourceRect.location.y),
        new Vector(100, 50),
      ),
    ]),
    sizeAdjust: "auto",
  });
  project.stageManager.add(node);
  project.nodeConnector.connectConnectableEntity(source, node);
  project.historyManager.recordStep();
  project.camera.bombMove(node.geometryCenter);
}

type ActiveChatController = {
  save: () => Promise<void>;
};

function formatSessionUpdatedAt(timestamp: number): string {
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(timestamp);
}

function AIChatWorkspace({ project, tabId }: { project: Project; tabId: string }) {
  const projectUri = project.uri.toString();
  const [model] = Settings.use("aiModel");
  const [sessionState, setSessionState] = useState<AIChatSessionProjectState | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [requesting, setRequesting] = useState(false);
  const [operationInProgress, setOperationInProgress] = useState(false);
  const operationInProgressRef = useRef(false);
  const [renamingSessionId, setRenamingSessionId] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");
  const [deletingSession, setDeletingSession] = useState<AIChatSessionSummary | null>(null);
  const activeChatController = useRef<ActiveChatController | null>(null);
  const references = useMemo(() => project.aiEngine.getProjectReferences(project), [project]);

  useEffect(
    () =>
      references.subscribe((snapshot) => {
        void AIProjectReferenceStore.save(project, snapshot).catch((saveError) => {
          toast.error(`AI 项目引用保存失败: ${saveError instanceof Error ? saveError.message : String(saveError)}`);
        });
      }),
    [project, references],
  );

  useEffect(() => {
    let cancelled = false;
    setSessionState(null);
    setLoadError(null);
    Promise.all([project.aiEngine.prepareProjectReferences(project), AIChatSessionStore.initializeProject(projectUri)])
      .then(([, initialSessionState]) => {
        if (cancelled) return;
        setSessionState(initialSessionState);
      })
      .catch((error) => {
        if (cancelled) return;
        setLoadError(error instanceof Error ? error.message : String(error));
      });
    return () => {
      cancelled = true;
    };
  }, [project, projectUri]);

  async function saveCurrentSession() {
    await activeChatController.current?.save();
  }

  async function runSessionOperation(operation: () => Promise<void>) {
    if (requesting || operationInProgressRef.current) return;
    operationInProgressRef.current = true;
    setOperationInProgress(true);
    try {
      await operation();
    } catch (error) {
      toast.error(`AI 会话操作失败: ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      operationInProgressRef.current = false;
      setOperationInProgress(false);
    }
  }

  function handleCreateSession() {
    void runSessionOperation(async () => {
      await saveCurrentSession();
      const nextState = await AIChatSessionStore.createSession(projectUri);
      setSessionState(nextState);
      setHistoryOpen(false);
    });
  }

  function handleSwitchSession(sessionId: string) {
    if (!sessionState || sessionState.index.activeSessionId === sessionId) {
      setHistoryOpen(false);
      return;
    }
    void runSessionOperation(async () => {
      await saveCurrentSession();
      const nextState = await AIChatSessionStore.setActiveSession(projectUri, sessionId);
      setSessionState(nextState);
      setHistoryOpen(false);
    });
  }

  function startRenaming(session: AIChatSessionSummary) {
    setRenamingSessionId(session.id);
    setRenameDraft(session.title);
  }

  function handleRenameSession() {
    const sessionId = renamingSessionId;
    if (!sessionId || !renameDraft.trim()) return;
    void runSessionOperation(async () => {
      const nextState = await AIChatSessionStore.renameSession(projectUri, sessionId, renameDraft);
      setSessionState(nextState);
      setRenamingSessionId(null);
      setRenameDraft("");
    });
  }

  function handleDeleteRequest(session: AIChatSessionSummary) {
    if (session.messageCount > 0) {
      setDeletingSession(session);
      return;
    }
    deleteSession(session.id);
  }

  function deleteSession(sessionId: string) {
    void runSessionOperation(async () => {
      if (sessionState?.index.activeSessionId === sessionId) await saveCurrentSession();
      const nextState = await AIChatSessionStore.deleteSession(projectUri, sessionId);
      setSessionState(nextState);
      setDeletingSession(null);
      setRenamingSessionId(null);
    });
  }

  function handleClose() {
    void runSessionOperation(async () => {
      await saveCurrentSession();
      TabWorkspace.close(tabId);
    });
  }

  const actionsDisabled = requesting || operationInProgress || !sessionState;

  return (
    <div className="from-background via-background to-muted/30 flex h-full flex-col bg-gradient-to-b">
      <div data-pg-drag-region className="border-border/70 flex items-center gap-2 border-b px-3 py-2">
        <div className="bg-primary/10 text-primary flex size-8 items-center justify-center rounded-xl">
          <Sparkles className="size-4" />
        </div>
        <div className="min-w-0 flex-1">
          <div className="truncate text-sm font-semibold">
            {sessionState?.activeSession.title ?? "Project Graph AI"}
          </div>
          <div className="text-muted-foreground truncate text-xs">{model}</div>
        </div>
        <Tooltip>
          <TooltipTrigger asChild>
            <Button
              variant="ghost"
              size="icon"
              aria-label="会话历史"
              disabled={!sessionState}
              onClick={() => setHistoryOpen(true)}
            >
              <History />
            </Button>
          </TooltipTrigger>
          <TooltipContent>会话历史</TooltipContent>
        </Tooltip>
        <Tooltip>
          <TooltipTrigger asChild>
            <Button
              variant="ghost"
              size="icon"
              aria-label="新建会话"
              disabled={actionsDisabled}
              onClick={handleCreateSession}
            >
              <Plus />
            </Button>
          </TooltipTrigger>
          <TooltipContent>新建会话</TooltipContent>
        </Tooltip>
        <Button
          variant="ghost"
          size="icon"
          aria-label="关闭 AI 窗口"
          disabled={requesting || operationInProgress}
          onClick={handleClose}
        >
          <X />
        </Button>
      </div>

      {loadError ? (
        <div className="text-destructive flex flex-1 items-center justify-center p-6 text-center text-sm">
          AI 会话加载失败：{loadError}
        </div>
      ) : !sessionState ? (
        <div className="text-muted-foreground flex flex-1 items-center justify-center text-sm">正在加载 AI 记忆…</div>
      ) : (
        <AIChatPanel
          key={sessionState.activeSession.id}
          project={project}
          session={sessionState.activeSession}
          references={references}
          onControllerChange={(controller) => {
            activeChatController.current = controller;
          }}
          onRequestingChange={setRequesting}
          onSessionSaved={setSessionState}
        />
      )}

      <Sheet open={historyOpen} onOpenChange={setHistoryOpen}>
        <SheetContent side="left" className="w-72 sm:max-w-72">
          <SheetHeader>
            <SheetTitle>会话历史</SheetTitle>
            <SheetDescription>每个会话保留独立的聊天上下文，共享当前项目的节点引用。</SheetDescription>
          </SheetHeader>
          <ScrollArea className="min-h-0 flex-1 px-3 pb-4">
            <div className="flex flex-col gap-1">
              {sessionState?.index.sessions.map((session) => {
                const isActive = session.id === sessionState.index.activeSessionId;
                const isRenaming = renamingSessionId === session.id;
                return (
                  <div
                    key={session.id}
                    className={cn("flex items-center rounded-md", isActive && "bg-accent text-accent-foreground")}
                  >
                    {isRenaming ? (
                      <div className="flex min-w-0 flex-1 items-center gap-1 p-1">
                        <Input
                          autoFocus
                          aria-label="会话标题"
                          value={renameDraft}
                          disabled={operationInProgress}
                          onChange={(event) => setRenameDraft(event.target.value)}
                          onKeyDown={(event) => {
                            if (event.key === "Enter") handleRenameSession();
                            if (event.key === "Escape") setRenamingSessionId(null);
                          }}
                        />
                        <Button
                          variant="ghost"
                          size="icon"
                          aria-label="保存标题"
                          disabled={!renameDraft.trim() || operationInProgress}
                          onClick={handleRenameSession}
                        >
                          <Check />
                        </Button>
                      </div>
                    ) : (
                      <button
                        type="button"
                        className="flex min-w-0 flex-1 cursor-pointer flex-col items-start gap-0.5 rounded-md px-2 py-2 text-left disabled:cursor-not-allowed disabled:opacity-50"
                        disabled={actionsDisabled}
                        onClick={() => handleSwitchSession(session.id)}
                      >
                        <span className="w-full truncate text-sm font-medium">{session.title}</span>
                        <span className="text-muted-foreground text-xs">
                          {formatSessionUpdatedAt(session.updatedAt)} · {session.messageCount} 条消息
                        </span>
                      </button>
                    )}
                    {!isRenaming && (
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button
                            variant="ghost"
                            size="icon"
                            aria-label={`${session.title} 的操作`}
                            disabled={actionsDisabled}
                          >
                            <MoreHorizontal />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuGroup>
                            <DropdownMenuItem onSelect={() => startRenaming(session)}>
                              <Pencil />
                              重命名
                            </DropdownMenuItem>
                            <DropdownMenuItem variant="destructive" onSelect={() => handleDeleteRequest(session)}>
                              <Trash2 />
                              删除
                            </DropdownMenuItem>
                          </DropdownMenuGroup>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    )}
                  </div>
                );
              })}
            </div>
          </ScrollArea>
        </SheetContent>
      </Sheet>

      <AlertDialog open={!!deletingSession} onOpenChange={(open) => !open && setDeletingSession(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>删除会话？</AlertDialogTitle>
            <AlertDialogDescription>
              “{deletingSession?.title}”中的聊天记录会从本地删除，但该会话已经修改的画布内容不会撤销。
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>取消</AlertDialogCancel>
            <AlertDialogAction
              disabled={operationInProgress}
              onClick={() => deletingSession && deleteSession(deletingSession.id)}
            >
              删除
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

function AIChatPanel({
  project,
  session,
  references,
  onControllerChange,
  onRequestingChange,
  onSessionSaved,
}: {
  project: Project;
  session: StoredAIChatSession;
  references: AIObjectReferenceRegistry;
  onControllerChange: (controller: ActiveChatController | null) => void;
  onRequestingChange: (requesting: boolean) => void;
  onSessionSaved: (state: AIChatSessionProjectState) => void;
}) {
  const [inputValue, setInputValue] = useState("");
  const messagesElRef = useRef<HTMLDivElement>(null);
  const [showTokenCount] = Settings.use("aiShowTokenCount");
  const [showDebug] = Settings.use("showDebug");
  const [autoApproveMcpTools, setAutoApproveMcpTools] = Settings.use("aiAutoApproveMcpTools");
  const autoApproveMcpToolsId = useId();
  const [apiBaseUrl] = Settings.use("aiApiBaseUrl");
  const [apiKey] = Settings.use("aiApiKey");
  const [model] = Settings.use("aiModel");
  const [manualContextWindow] = Settings.use("aiContextWindow");
  const contextWindowTokenLimitRef = useRef<number | undefined>(undefined);
  const conversation = useMemo(
    () => project.aiEngine.createConversation(project, references, () => contextWindowTokenLimitRef.current),
    [project, references],
  );
  const [selectedCount, setSelectedCount] = useState(0);
  const [sessionLoaded, setSessionLoaded] = useState(false);
  const [contextWindowState, setContextWindowState] = useState<ContextWindowState>({ status: "loading" });
  const projectUri = project.uri.toString();
  const messagesRef = useRef<UIMessage<AIMessageMetadata>[]>(session.messages);
  const lastSavedMessagesRef = useRef<UIMessage<AIMessageMetadata>[]>(session.messages);

  const persistMessages = useCallback(
    async (nextMessages: UIMessage<AIMessageMetadata>[]) => {
      await AIProjectReferenceStore.save(project, references.exportSnapshot());
      const nextState = await AIChatSessionStore.saveSession(projectUri, session.id, nextMessages);
      lastSavedMessagesRef.current = nextMessages;
      onSessionSaved(nextState);
    },
    [onSessionSaved, project, projectUri, references, session.id],
  );

  const { messages, setMessages, sendMessage, stop, status, addToolApprovalResponse } = useChat<
    UIMessage<AIMessageMetadata>
  >({
    id: session.id,
    transport: conversation.transport,
    experimental_throttle: 50,
    sendAutomaticallyWhen: lastAssistantMessageIsCompleteWithApprovalResponses,
    onError: (err) => {
      toast.error(`AI 请求失败: ${err.message || err.toString() || JSON.stringify(err)}`);
    },
  });
  const requesting = status === "submitted" || status === "streaming";
  const tokenUsage = useMemo(() => getTokenUsage(messages), [messages]);
  const contextUsage = useMemo(() => getCurrentContextUsage(messages), [messages]);

  useEffect(() => {
    messagesRef.current = messages;
  }, [messages]);

  useEffect(() => {
    messagesElRef.current?.scrollTo({ top: messagesElRef.current.scrollHeight, behavior: "smooth" });
  }, [messages]);

  useEffect(() => {
    let cancelled = false;
    contextWindowTokenLimitRef.current = undefined;
    setContextWindowState({ status: "loading" });
    resolveAIModelContextWindow({
      apiBaseUrl,
      apiKey,
      model,
      manualTokenLimit: manualContextWindow,
    })
      .then((info) => {
        if (cancelled) return;
        contextWindowTokenLimitRef.current = info?.tokenLimit;
        setContextWindowState(info ? { status: "ready", info } : { status: "unknown" });
      })
      .catch((contextWindowError) => {
        if (cancelled) return;
        contextWindowTokenLimitRef.current = undefined;
        setContextWindowState({
          status: "error",
          message: contextWindowError instanceof Error ? contextWindowError.message : String(contextWindowError),
        });
      });
    return () => {
      cancelled = true;
    };
  }, [apiBaseUrl, apiKey, manualContextWindow, model]);

  useEffect(() => {
    setMessages(session.messages);
    messagesRef.current = session.messages;
    lastSavedMessagesRef.current = session.messages;
    setSessionLoaded(true);
  }, [session.id, setMessages]);

  useEffect(() => {
    onRequestingChange(requesting);
    return () => onRequestingChange(false);
  }, [onRequestingChange, requesting]);

  useEffect(() => {
    onControllerChange({
      save: async () => {
        await persistMessages(messagesRef.current);
      },
    });
    return () => onControllerChange(null);
  }, [onControllerChange, persistMessages]);

  useEffect(() => {
    if (!sessionLoaded || requesting || messages === lastSavedMessagesRef.current) return;
    const timeout = window.setTimeout(() => {
      void persistMessages(messages).catch((saveError) => {
        toast.error(`AI 会话保存失败: ${saveError instanceof Error ? saveError.message : String(saveError)}`);
      });
    }, 250);
    return () => window.clearTimeout(timeout);
  }, [messages, persistMessages, requesting, sessionLoaded]);

  useEffect(() => {
    const interval = setInterval(() => {
      setSelectedCount(project.stageManager.getSelectedEntities().length);
    }, 300);
    return () => clearInterval(interval);
  }, [project]);

  useEffect(() => {
    if (pendingInitialText) {
      const text = pendingInitialText;
      const prompt = pendingInitialPrompt;
      pendingInitialText = null;
      pendingInitialPrompt = null;

      if (prompt) {
        setInputValue(`${prompt}\n\n---\n\n${text}`);
      } else {
        setInputValue(text);
      }
    }
  }, []);

  function handleUserSend() {
    const text = inputValue.trim();
    if (!text || requesting || !sessionLoaded) return;
    const selectedEntities = project.stageManager.getSelectedEntities();
    const selectedAssociations = project.stageManager.getSelectedAssociations();
    const selectedRefs = [...selectedEntities, ...selectedAssociations].map((object) =>
      references.getOrCreateRef(object),
    );
    const prefix = selectedRefs.length > 0 ? `[selected: ${selectedRefs.join(" ")}]\n` : "";
    const messageText = prefix + text;
    project.aiEngine.getRequestTraceBuffer().capturePendingInput(session.id, messageText);
    sendMessage({ text: messageText });
    setInputValue("");
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      e.stopPropagation();
      handleUserSend();
    }
  }

  const ObjectRefCode = useCallback(
    ({ children, ...props }: any) => {
      const text = typeof children === "string" ? children : String(children ?? "");
      const stageObject = references.tryResolve(text);
      if (!stageObject || !isEntity(stageObject)) {
        return <code {...props}>{children}</code>;
      }

      const hasColor = "color" in stageObject && stageObject.color instanceof Color;
      const bgColor = hasColor ? (stageObject.color as Color).toHexStringWithoutAlpha() : undefined;
      const textColor = hasColor ? getContrastTextColor(stageObject.color as Color) : undefined;

      const hasText = "text" in stageObject && typeof stageObject.text === "string";
      const textPreview = hasText
        ? `${(stageObject.text as string).split("\n")[0]} `
        : `${getOriginalNameOf(stageObject.constructor)} ${text}`;

      const handleClick = () => {
        project.stageManager.clearSelectAll();
        stageObject.isSelected = true;
        const center = stageObject.collisionBox.getRectangle().center;
        project.camera.bombMove(center);
      };

      return (
        <Tooltip>
          <TooltipTrigger asChild>
            <span
              className="hover:ring-primary/50 inline-flex cursor-pointer items-center rounded px-1.5 py-0.5 text-xs transition-all hover:ring-2"
              style={bgColor ? { backgroundColor: bgColor, color: textColor } : undefined}
              onClick={handleClick}
            >
              {textPreview}
            </span>
          </TooltipTrigger>
          <TooltipContent>{text}</TooltipContent>
        </Tooltip>
      );
    },
    [project, references],
  );

  const markdownComponents = useMemo(() => ({ inlineCode: ObjectRefCode }), [ObjectRefCode]);

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div ref={messagesElRef} className="flex-1 overflow-y-auto px-3 py-4">
        {messages.length === 0 ? (
          <div className="text-muted-foreground flex h-full flex-col items-center justify-center gap-3 text-center">
            <Bot className="size-10" />
            <div className="text-foreground font-medium">说说你想怎么改这张图</div>
            <div className="max-w-72 text-sm">
              例如：整理当前选中的节点、生成一棵知识树、批量改颜色，或者让它先读取画布再规划。
            </div>
          </div>
        ) : (
          <div className="flex flex-col gap-4">
            {messages.map((message, index) => (
              <MessageBubble
                key={message.id}
                message={message as any}
                components={markdownComponents}
                project={project}
                selectedCount={selectedCount}
                isLast={index === messages.length - 1}
                requesting={requesting}
                onToolApproval={async (id, approved) => {
                  await addToolApprovalResponse({ id, approved });
                }}
              />
            ))}
          </div>
        )}
      </div>

      <div className="border-border/70 border-t p-3">
        <div className="mb-2 flex items-center gap-2 text-xs">
          {selectedCount > 0 && (
            <>
              <Paperclip className="size-3.5" />
              <span>已选中 {selectedCount} 个节点</span>
            </>
          )}
          {showTokenCount && (
            <Tooltip>
              <TooltipTrigger>
                <div className="text-muted-foreground flex items-center gap-1.5">
                  <User className="size-3.5" />
                  <span>{formatTokenCount(tokenUsage.inputTokens)}</span>
                  <span></span>
                  <Bot className="size-3.5" />
                  <span>{formatTokenCount(tokenUsage.outputTokens)}</span>
                </div>
              </TooltipTrigger>
              <TooltipContent>Token 数量仅供参考，请以服务商实际计费为准</TooltipContent>
            </Tooltip>
          )}
          <div className="flex-1" />
          <span className="text-muted-foreground">
            {!sessionLoaded ? "正在加载记忆" : requesting ? "正在思考" : "准备就绪"}
          </span>
          {requesting ? (
            <Button size="sm" variant="outline" className="h-8 cursor-pointer" onClick={stop}>
              <Square className="size-4" />
            </Button>
          ) : (
            <Button
              size="sm"
              className="h-8 cursor-pointer"
              onClick={handleUserSend}
              disabled={!sessionLoaded || !inputValue.trim()}
            >
              <Send className="size-4" />
            </Button>
          )}
        </div>
        <Textarea
          placeholder="让 AI 读取画布、创建节点、连线、整理选区..."
          className="max-h-36 resize-none"
          onChange={(e) => setInputValue(e.target.value)}
          onKeyDown={handleKeyDown}
          value={inputValue}
          disabled={requesting || !sessionLoaded}
        />
        <div className="mt-2 flex items-center gap-2">
          <Switch
            id={autoApproveMcpToolsId}
            checked={autoApproveMcpTools}
            disabled={requesting || !sessionLoaded}
            onCheckedChange={setAutoApproveMcpTools}
            aria-label="自动批准 MCP 工具"
          />
          <label htmlFor={autoApproveMcpToolsId} className="flex cursor-pointer items-center gap-1.5 text-xs">
            <ShieldCheck className="size-3.5" />
            自动批准 MCP 工具
          </label>
          <Tooltip>
            <TooltipTrigger asChild>
              <button
                type="button"
                className="text-muted-foreground cursor-help text-xs underline decoration-dotted underline-offset-2"
              >
                安全说明
              </button>
            </TooltipTrigger>
            <TooltipContent className="max-w-72">
              开启后 MCP 工具无需逐次批准；本地 stdio 进程首次启动仍需单独确认。设置从下一次请求开始生效。
            </TooltipContent>
          </Tooltip>
        </div>
        <ContextWindowUsage
          usage={contextUsage}
          state={contextWindowState}
          sessionTotalTokens={tokenUsage.totalTokens}
        />
        {showDebug && (
          <AIRequestTraceView buffer={project.aiEngine.getRequestTraceBuffer()} activeSessionId={session.id} />
        )}
      </div>
    </div>
  );
}

function getTokenUsage(messages: UIMessage<AIMessageMetadata>[]) {
  return messages.reduce(
    (usage, message) => {
      usage.inputTokens += message.metadata?.inputTokens ?? 0;
      usage.outputTokens += message.metadata?.outputTokens ?? 0;
      usage.totalTokens += message.metadata?.totalTokens ?? 0;
      return usage;
    },
    { inputTokens: 0, outputTokens: 0, totalTokens: 0 },
  );
}

function formatTokenCount(value: number) {
  return value.toLocaleString();
}

type CurrentContextUsage = {
  inputTokens: number;
  outputTokens: number;
  usedTokens: number;
};

function getCurrentContextUsage(messages: UIMessage<AIMessageMetadata>[]): CurrentContextUsage | null {
  for (let index = messages.length - 1; index >= 0; index--) {
    const metadata = messages[index].metadata;
    if (typeof metadata?.lastStepInputTokens !== "number") continue;
    const outputTokens = metadata.lastStepOutputTokens ?? 0;
    return {
      inputTokens: metadata.lastStepInputTokens,
      outputTokens,
      usedTokens: metadata.lastStepInputTokens + outputTokens,
    };
  }
  return null;
}

function formatCompactTokenCount(value: number) {
  return new Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 1 }).format(value);
}

function ContextWindowUsage({
  usage,
  state,
  sessionTotalTokens,
}: {
  usage: CurrentContextUsage | null;
  state: ContextWindowState;
  sessionTotalTokens: number;
}) {
  const tokenLimit = state.status === "ready" ? state.info.tokenLimit : undefined;
  const percentage = tokenLimit && usage ? Math.min(100, (usage.usedTokens / tokenLimit) * 100) : 0;
  const indicatorVariant = percentage >= 90 ? "destructive" : percentage >= 70 ? "caution" : "default";
  const usedText = usage ? formatCompactTokenCount(usage.usedTokens) : "--";
  const summary =
    state.status === "loading"
      ? `${usedText} / 正在获取上限`
      : state.status === "ready"
        ? `${usedText} / ${formatCompactTokenCount(state.info.tokenLimit)} · ${usage ? `${((usage.usedTokens / state.info.tokenLimit) * 100).toFixed(1)}%` : "--"}`
        : state.status === "error"
          ? `${usedText} / 获取失败`
          : `${usedText} / 上限未知`;
  const source = state.status === "ready" ? (state.info.source === "openrouter" ? "OpenRouter" : "手动设置") : "未知";

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <div
          className="mt-2 flex flex-col gap-1 outline-none"
          tabIndex={0}
          role="status"
          aria-label={`上下文窗口 ${summary}`}
        >
          <div className="text-muted-foreground flex items-center justify-between text-xs">
            <span>上下文</span>
            <span>{summary}</span>
          </div>
          <Progress
            value={percentage}
            indicatorVariant={indicatorVariant}
            className="h-1"
            aria-label="上下文窗口使用率"
          />
        </div>
      </TooltipTrigger>
      <TooltipContent>
        <div className="flex min-w-56 flex-col gap-1">
          <div>占用量按最后一步模型输入与输出计算</div>
          <div>最后输入：{usage ? formatTokenCount(usage.inputTokens) : "暂无"}</div>
          <div>最后输出：{usage ? formatTokenCount(usage.outputTokens) : "暂无"}</div>
          <div>会话累计计费：{formatTokenCount(sessionTotalTokens)}</div>
          <div>上下文上限来源：{source}</div>
          {state.status === "error" && <div>错误：{state.message}</div>}
          {state.status === "unknown" && <div>可在 AI 设置中手动填写上下文窗口大小</div>}
        </div>
      </TooltipContent>
    </Tooltip>
  );
}

function MessageBubble({
  message,
  components,
  project,
  selectedCount,
  isLast,
  requesting,
  onToolApproval,
}: {
  message: any;
  components?: Record<string, React.ComponentType<any>>;
  project: Project;
  selectedCount: number;
  isLast: boolean;
  requesting: boolean;
  onToolApproval: (id: string, approved: boolean) => Promise<void>;
}) {
  const isUser = message.role === "user";
  const parts = Array.isArray(message.parts) ? message.parts : [];
  const bubbles = isUser ? [parts] : splitPartsByStepStart(parts);

  return (
    <div className={cn("flex gap-2", isUser ? "justify-end" : "justify-start")}>
      {!isUser && (
        <div className="bg-primary/10 text-primary mt-1 flex size-7 shrink-0 items-center justify-center rounded-full">
          <Bot className="size-4" />
        </div>
      )}
      <div className={cn("flex max-w-[88%] flex-col gap-2", isUser ? "items-end" : "items-start")}>
        {bubbles.length > 0 ? (
          bubbles.map((bubbleParts, bubbleIndex) => (
            <div
              key={bubbleIndex}
              className={cn(
                "flex max-w-full min-w-0 cursor-text flex-col gap-2 rounded-2xl px-3 py-2 text-sm select-text",
                isUser
                  ? "bg-accent text-accent-foreground rounded-br-md"
                  : "bg-card border-border/70 rounded-bl-md border shadow-sm",
              )}
            >
              {bubbleParts.length > 0 ? (
                bubbleParts.map((part: any, index: number) => (
                  <MessagePart
                    key={part.toolCallId ?? `${part.type}-${bubbleIndex}-${index}`}
                    part={part}
                    components={components}
                    isAnimating={!isUser && requesting}
                    showCaret={!isUser && isLast}
                    onToolApproval={onToolApproval}
                  />
                ))
              ) : (
                <Streamdown
                  className="pg-ai-markdown"
                  plugins={{ code }}
                  components={components}
                  animated={!isUser}
                  isAnimating={!isUser && requesting}
                  caret={!isUser && isLast ? "circle" : undefined}
                >
                  {String(message.content ?? "")}
                </Streamdown>
              )}
            </div>
          ))
        ) : (
          <div
            className={cn(
              "max-w-full min-w-0 cursor-text rounded-2xl px-3 py-2 text-sm select-text",
              isUser
                ? "bg-accent text-accent-foreground rounded-br-md"
                : "bg-card border-border/70 rounded-bl-md border shadow-sm",
            )}
          >
            <Streamdown
              className="pg-ai-markdown"
              plugins={{ code }}
              components={components}
              animated={!isUser}
              isAnimating={!isUser && requesting}
              caret={!isUser && isLast ? "circle" : undefined}
            >
              {String(message.content ?? "")}
            </Streamdown>
          </div>
        )}
        {!isUser && selectedCount === 1 && parts.some((p: any) => p.type === "text") && (!isLast || !requesting) && (
          <button
            className="text-muted-foreground hover:text-foreground mt-1 flex cursor-pointer items-center self-end text-xs"
            onClick={() => createAnswerNode(message, project)}
          >
            <Plus className="size-3.5" />
          </button>
        )}
      </div>
      {isUser && (
        <div className="bg-accent text-accent-foreground mt-1 flex size-7 shrink-0 items-center justify-center rounded-full">
          <User className="size-4" />
        </div>
      )}
    </div>
  );
}

function splitPartsByStepStart(parts: any[]) {
  const bubbles: any[][] = [];
  let current: any[] = [];

  for (const part of parts) {
    if (part.type === "step-start") {
      if (current.length > 0) {
        bubbles.push(current);
        current = [];
      }
      continue;
    }
    current.push(part);
  }

  if (current.length > 0) {
    bubbles.push(current);
  }

  return bubbles;
}

function MessagePart({
  part,
  components,
  isAnimating,
  showCaret,
  onToolApproval,
}: {
  part: any;
  components?: Record<string, React.ComponentType<any>>;
  isAnimating?: boolean;
  showCaret?: boolean;
  onToolApproval: (id: string, approved: boolean) => Promise<void>;
}) {
  if (part.type === "text") {
    return (
      <Streamdown
        className="pg-ai-markdown"
        plugins={{ code }}
        components={components}
        animated={isAnimating}
        isAnimating={isAnimating}
        caret={showCaret ? "circle" : undefined}
      >
        {part.text ?? ""}
      </Streamdown>
    );
  }
  if (part.type === "reasoning") {
    return <ReasoningPart part={part} />;
  }
  if (isAIToolPart(part)) {
    return <ToolPart part={part} onToolApproval={onToolApproval} />;
  }
  return (
    <pre className="text-muted-foreground overflow-auto text-xs">unknown part: {JSON.stringify(part, null, 2)}</pre>
  );
}

function ReasoningPart({ part }: { part: any }) {
  const streaming = part.state === "streaming";
  const [open, setOpen] = useState(streaming);
  const userToggled = useRef(false);
  const wasStreaming = useRef(streaming);

  useEffect(() => {
    // 只在流式结束后自动收起一次，用户手动展开过就不再干预
    if (wasStreaming.current && !streaming && !userToggled.current) setOpen(false);
    wasStreaming.current = streaming;
  }, [streaming]);

  return (
    <Collapsible
      open={open}
      onOpenChange={(next) => {
        userToggled.current = true;
        setOpen(next);
      }}
      className="group/reasoning min-w-0 self-stretch"
    >
      <CollapsibleTrigger className="text-muted-foreground hover:text-foreground flex cursor-pointer items-center gap-1.5 text-xs">
        <ChevronRight className="size-3 shrink-0 transition-transform group-data-[state=open]/reasoning:rotate-90" />
        <span>{streaming ? "思考中" : "思考过程"}</span>
      </CollapsibleTrigger>
      <CollapsibleContent className="animate-none!">
        <div className="text-muted-foreground mt-1.5 border-l-2 pl-2 text-xs leading-relaxed wrap-anywhere whitespace-pre-wrap">
          {part.text ?? part.reasoning ?? ""}
        </div>
      </CollapsibleContent>
    </Collapsible>
  );
}

function ToolPart({
  part,
  onToolApproval,
}: {
  part: any;
  onToolApproval: (id: string, approved: boolean) => Promise<void>;
}) {
  const name = getAIToolPartName(part);
  const done = part.state === "output-available";
  const failed = part.state === "output-error";

  if (part.state === "approval-requested") {
    return <ToolApprovalPart name={name} part={part} onToolApproval={onToolApproval} />;
  }

  return (
    <Collapsible className="group/collapsible">
      <CollapsibleTrigger className="text-muted-foreground hover:text-foreground flex cursor-pointer items-center gap-2 text-xs">
        {done ? <Check className="size-4" /> : <X className={cn("size-4", failed && "text-destructive")} />}
        <span>{name}</span>
        <span>{toolStateText(part.state)}</span>
        <ChevronRight className="size-3 transition-transform group-data-[state=open]/collapsible:rotate-90" />
      </CollapsibleTrigger>
      <CollapsibleContent className="bg-muted/60 mt-2 animate-none! rounded-lg px-3 py-2">
        <Streamdown className="pg-ai-markdown" plugins={{ code }}>
          {`\`\`\`json\n${JSON.stringify({ input: part.input, output: part.output, error: part.errorText }, null, 2)}\n\`\`\``}
        </Streamdown>
      </CollapsibleContent>
    </Collapsible>
  );
}

function ToolApprovalPart({
  name,
  part,
  onToolApproval,
}: {
  name: string;
  part: any;
  onToolApproval: (id: string, approved: boolean) => Promise<void>;
}) {
  const [submitting, setSubmitting] = useState(false);
  const respond = async (approved: boolean) => {
    if (submitting) return;
    setSubmitting(true);
    try {
      await onToolApproval(part.approval.id, approved);
    } catch (error) {
      toast.error(`提交工具审批失败：${error instanceof Error ? error.message : String(error)}`);
      setSubmitting(false);
    }
  };

  return (
    <div className="flex flex-col gap-2">
      <div className="text-muted-foreground text-xs">
        <span className="font-mono">{name}</span> 请求执行
      </div>
      <pre className="bg-muted max-h-48 overflow-auto rounded-md p-2 font-mono text-xs select-text">
        {JSON.stringify(part.input, null, 2)}
      </pre>
      <div className="flex justify-end gap-2">
        <Button
          size="sm"
          className="h-7 px-2"
          variant="outline"
          disabled={submitting}
          onClick={() => void respond(false)}
        >
          拒绝
        </Button>
        <Button size="sm" className="h-7 px-2" disabled={submitting} onClick={() => void respond(true)}>
          允许本次调用
        </Button>
      </div>
    </div>
  );
}

function toolStateText(state: string | undefined) {
  switch (state) {
    case "input-streaming":
      return "准备参数";
    case "input-available":
      return "执行中";
    case "approval-requested":
      return "等待批准";
    case "approval-responded":
      return "已处理批准";
    case "output-available":
      return "完成";
    case "output-error":
      return "失败";
    default:
      return state ?? "";
  }
}

AIWindow.open = () => {
  createSubWindow("AIWindow", {
    title: "",
    contextTarget: "activeResourceTab",
    closable: false,
    titleBarOverlay: true,
    closeOnEscape: false,
    children: (tab) => <AIWindow tabId={tab.id} />,
    rect: new Rectangle(new Vector(8, 88), new Vector(380, window.innerHeight - 96)),
  });
};
