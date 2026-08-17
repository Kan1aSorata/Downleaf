import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowClockwise,
  ArrowCounterClockwise,
  Article,
  CaretDown,
  CaretLeft,
  CaretRight,
  Check,
  CheckSquare,
  Code,
  Columns,
  DotsThree,
  FileText,
  ImageSquare,
  LinkSimple,
  Minus,
  PaintBrush,
  PencilSimple,
  Plus,
  Quotes,
  SidebarSimple,
  TextB,
  TextH,
  TextItalic,
  TextStrikethrough,
  TextUnderline,
} from "@phosphor-icons/react";

const DEFAULT_OUTLINE_WIDTH = 280;
const MIN_OUTLINE_WIDTH = 180;
const MAX_OUTLINE_WIDTH = 480;

const INITIAL_SECTIONS = [
  {
    id: "downleaf",
    level: 1,
    title: "Downleaf — 为长文档而生",
    paragraphs: [
      "一个极简、快速、完全属于你的 Mac Markdown 编辑器。打开文件就开始写，不需要导入知识库，也没有账号、同步或格式绑架。",
      "这个可交互原型把正文放在视觉中心，并用右侧快速大纲解决长文档里的定位问题。试着点击大纲、折叠章节，或者拖动它左侧的分隔线。",
    ],
    quote: "核心承诺：打开即写，长文档依然流畅，文件永远属于用户。",
  },
  {
    id: "goals",
    level: 2,
    title: "01 设计目标",
    paragraphs: [
      "Downleaf 不试图成为另一个复杂的知识管理系统。它只专注于把编辑、阅读和文档导航这三件事做到足够安静、可靠和高效。",
    ],
  },
  {
    id: "open-and-write",
    level: 3,
    title: "打开即写",
    paragraphs: [
      "双击任意 .md 文件后，焦点直接落在正文。没有欢迎页、工作区向导或需要先理解的产品概念。最近文稿和 Finder 中的文件保持同一套心智模型。",
    ],
  },
  {
    id: "files-belong-to-you",
    level: 3,
    title: "文件始终属于用户",
    paragraphs: [
      "应用直接读写标准 Markdown，尊重原编码、换行符和相对路径。Git、终端、云盘或其他编辑器修改文件后，Downleaf 会安全地同步变化。",
    ],
  },
  {
    id: "editor-experience",
    level: 2,
    title: "02 编辑体验",
    paragraphs: [
      "正文区域沿用原生文本编辑习惯：选择、撤销、拼写检查、输入法组合态和系统服务都应该像 TextEdit 一样自然，但 Markdown 结构更清晰。",
    ],
  },
  {
    id: "keyboard-first",
    level: 3,
    title: "键盘优先，而不是键盘限定",
    paragraphs: [
      "粗体、斜体、链接、列表、标题和任务状态都有快捷键；所有命令也能从命令面板搜索。鼠标工具栏保持轻量，只在需要时提供可发现性。",
    ],
    bullets: ["⌘K 打开命令面板", "⌘E 切换编辑与阅读", "⌥⌘E 打开左右分栏", "⌥⌘O 显示或隐藏大纲"],
  },
  {
    id: "cjk-and-long-docs",
    level: 3,
    title: "中文输入与长文档",
    paragraphs: [
      "语法高亮只更新变化行和可见区域，不打断中文、日文或韩文输入法的组合状态。解析、统计和预览全部在输入路径之外异步完成。",
    ],
  },
  {
    id: "outline",
    level: 2,
    title: "03 快速大纲",
    paragraphs: [
      "大纲常驻内容区最右侧，从 H1–H6 自动生成。它不是另一套文档结构，只是当前 Markdown 标题的轻量索引。",
    ],
  },
  {
    id: "resize-outline",
    level: 3,
    title: "拖拽调整宽度",
    paragraphs: [
      "分隔线视觉上只有 1 像素，但左右拥有更宽的命中区域。默认宽度为 280 像素，可在 180–480 像素之间连续调整；双击分隔线即可恢复默认宽度。",
      "当前宽度会保存在本机。刷新页面后仍会保持你的选择，这模拟了正式 Mac 应用的窗口恢复行为。",
    ],
  },
  {
    id: "follow-position",
    level: 3,
    title: "当前位置自动跟随",
    paragraphs: [
      "滚动正文时，位于视口上方约四分之一处的章节会成为当前章节。大纲同步高亮并确保条目可见，但当你主动滚动大纲时会短暂停止自动拉回。",
    ],
  },
  {
    id: "outline-keyboard",
    level: 3,
    title: "完整键盘导航",
    paragraphs: [
      "聚焦大纲后，可以用上下方向键移动，左右方向键折叠或展开，Return 跳转，Home 和 End 到达首尾。长标题保持单行，并在悬停时显示全文。",
    ],
  },
  {
    id: "view-modes",
    level: 2,
    title: "04 三种阅读方式",
    paragraphs: [
      "同一份文件可以在源码编辑、左右分屏和纯阅读之间瞬时切换。模式变化不会改写 Markdown，也不会丢失当前章节。",
    ],
  },
  {
    id: "edit-mode",
    level: 3,
    title: "源码编辑",
    paragraphs: [
      "默认模式保留 Markdown 语法的可见性和可预测光标。正文宽度受到控制，让长时间写作保持舒适。你可以直接修改本页标题和段落。",
    ],
  },
  {
    id: "split-mode",
    level: 3,
    title: "左右分屏",
    paragraphs: [
      "左侧继续编辑，右侧展示排版后的阅读效果。两侧按照章节近似同步滚动，优先保证稳定，而不是追求容易抖动的逐像素绑定。",
    ],
  },
  {
    id: "reading-mode",
    level: 3,
    title: "纯阅读",
    paragraphs: [
      "阅读模式隐藏编辑噪音，保留选择、复制、查找和大纲导航。代码块、引用、列表和链接使用克制的对比度，避免像网页主题一样抢走注意力。",
    ],
  },
  {
    id: "performance",
    level: 2,
    title: "05 性能预算",
    paragraphs: [
      "性能不是发布后的优化项，而是产品契约。启动、输入、滚动、内存和大文件处理都有可重复测量的目标。",
    ],
  },
  {
    id: "latency-budget",
    level: 3,
    title: "启动与输入延迟",
    paragraphs: [
      "Apple Silicon 冷启动目标小于 400 ms；普通文档输入到屏幕更新的 P95 目标小于 16 ms。预览不可见时，不创建额外渲染实例。",
    ],
    code: "cold_launch_p95 < 400ms\ninput_latency_p95 < 16ms\nscroll_frame_budget = 8.3ms",
  },
  {
    id: "safe-mode",
    level: 3,
    title: "大文件安全模式",
    paragraphs: [
      "超过 10 MB 或 100,000 行时，应用暂停实时预览和复杂统计，只保留编辑、搜索、保存、可见区域高亮和轻量标题索引。",
    ],
  },
  {
    id: "technology",
    level: 2,
    title: "06 技术路线",
    paragraphs: [
      "正式产品只面向 macOS，因此用原生能力换取更好的输入法、文本系统、无障碍和能耗表现。整体采用模块化单体，避免 MVP 被工程复杂度拖慢。",
    ],
  },
  {
    id: "swiftui-appkit",
    level: 3,
    title: "SwiftUI 外壳 + AppKit 内核",
    paragraphs: [
      "SwiftUI 负责窗口、工具栏和设置，AppKit 负责文档生命周期、分栏和核心文本编辑。大纲使用 NSOutlineView，内容区使用 NSSplitViewController。",
    ],
  },
  {
    id: "textkit",
    level: 3,
    title: "TextKit 2 编辑器",
    paragraphs: [
      "核心编辑器建立在 NSTextView 与 TextKit 2 上，保留系统成熟的选择、撤销、输入法和 VoiceOver 能力，只增加 Markdown 所需的薄层行为。",
    ],
  },
  {
    id: "mvp",
    level: 2,
    title: "07 MVP 验收",
    paragraphs: [
      "首个公开测试版必须证明基础编辑可靠、外部文件变化安全、三种视图可用，并且右侧大纲在长文档中确实节省定位时间。",
    ],
  },
  {
    id: "p0",
    level: 3,
    title: "P0 功能",
    paragraphs: [
      "新建、打开、保存、撤销、语法高亮、查找替换、三种视图、快速大纲、自动保存、崩溃恢复和外部变更处理都属于首发范围。",
    ],
    bullets: ["标准 Markdown 直接读写", "输入与滚动不被解析阻塞", "大纲可折叠、可调宽、可用键盘操作", "暗色与浅色模式均满足可读性"],
  },
  {
    id: "not-doing",
    level: 3,
    title: "明确不做的事情",
    paragraphs: [
      "首版不做知识库、双链、账号、云同步、多人协作、插件市场或内置 AI 聊天。这些边界让产品有机会把一个编辑器真正做好。",
    ],
  },
  {
    id: "next",
    level: 2,
    title: "08 下一步",
    paragraphs: [
      "用这个原型确认布局密度与大纲操作后，下一阶段将用 Swift 6 建立原生工程，先完成真实文件读写、TextKit 2 编辑和 NSSplitView 的大纲宽度恢复。",
    ],
  },
];

const INITIAL_DOCUMENTS = [
  {
    id: "product-design",
    name: "Downleaf 产品设计稿.md",
    meta: "刚刚",
    path: "~/Documents/Downleaf 产品设计稿.md",
    sections: INITIAL_SECTIONS,
    dirty: false,
    isBuffer: false,
  },
  {
    id: "roadmap",
    name: "2026 产品路线图.md",
    meta: "昨天",
    path: "~/Documents/2026 产品路线图.md",
    sections: INITIAL_SECTIONS,
    dirty: false,
    isBuffer: false,
  },
  {
    id: "performance-checklist",
    name: "性能验收清单.md",
    meta: "8 月 12 日",
    path: "~/Documents/性能验收清单.md",
    sections: INITIAL_SECTIONS,
    dirty: false,
    isBuffer: false,
  },
  {
    id: "release-notes",
    name: "发布说明草稿.md",
    meta: "8 月 9 日",
    path: "~/Documents/发布说明草稿.md",
    sections: INITIAL_SECTIONS,
    dirty: false,
    isBuffer: false,
  },
];

function createBlankSections(documentId) {
  return [
    {
      id: `${documentId}-start`,
      level: 1,
      title: "",
      paragraphs: [""],
    },
  ];
}

function ensureMarkdownExtension(name) {
  const trimmed = name.trim() || "未命名文稿";
  return /\.md$/i.test(trimmed) ? trimmed : `${trimmed}.md`;
}

function fileNameFromPath(path) {
  const normalized = path.trim().replace(/\\/g, "/");
  return ensureMarkdownExtension(normalized.split("/").filter(Boolean).at(-1) || "未命名文稿");
}

function readStoredNumber(key, fallback) {
  try {
    const value = Number(window.localStorage.getItem(key));
    return Number.isFinite(value) && value > 0 ? value : fallback;
  } catch {
    return fallback;
  }
}

function readStoredBoolean(key, fallback) {
  try {
    const value = window.localStorage.getItem(key);
    return value === null ? fallback : value === "true";
  } catch {
    return fallback;
  }
}

function readStoredSet(key) {
  try {
    const value = JSON.parse(window.localStorage.getItem(key) || "[]");
    return new Set(Array.isArray(value) ? value : []);
  } catch {
    return new Set();
  }
}

function buildOutlineTree(items) {
  const roots = [];
  const stack = [];

  items.forEach((item) => {
    const node = {
      ...item,
      title: item.title?.trim() || "未命名标题",
      children: [],
      parentId: null,
    };

    while (stack.length && stack[stack.length - 1].level >= node.level) {
      stack.pop();
    }

    if (stack.length) {
      node.parentId = stack[stack.length - 1].id;
      stack[stack.length - 1].children.push(node);
    } else {
      roots.push(node);
    }

    stack.push(node);
  });

  return roots;
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function DocumentSection({
  section,
  editable,
  registerHeading,
  onCommit,
  onDirty,
}) {
  const HeadingTag = `h${Math.min(section.level, 6)}`;

  const commitText = (kind, index, event) => {
    const value = event.currentTarget.innerText.trim();
    onCommit(section.id, kind, index, value);
  };

  return (
    <section className={`document-section level-${section.level}`} data-section-id={section.id}>
      <HeadingTag
        ref={(node) => registerHeading(section.id, node)}
        className="document-heading"
        data-heading-id={section.id}
        data-placeholder="标题"
        contentEditable={editable}
        suppressContentEditableWarning
        spellCheck={editable}
        onInput={onDirty}
        onBlur={(event) => commitText("title", 0, event)}
      >
        {section.title}
      </HeadingTag>

      {section.paragraphs?.map((paragraph, index) => (
        <p
          key={`${section.id}-paragraph-${index}`}
          data-placeholder="开始写作…"
          contentEditable={editable}
          suppressContentEditableWarning
          spellCheck={editable}
          onInput={onDirty}
          onBlur={(event) => commitText("paragraph", index, event)}
        >
          {paragraph}
        </p>
      ))}

      {section.quote ? (
        <blockquote
          contentEditable={editable}
          suppressContentEditableWarning
          spellCheck={editable}
          onInput={onDirty}
          onBlur={(event) => commitText("quote", 0, event)}
        >
          {section.quote}
        </blockquote>
      ) : null}

      {section.bullets ? (
        <ul>
          {section.bullets.map((item, index) => (
            <li
              key={`${section.id}-bullet-${index}`}
              contentEditable={editable}
              suppressContentEditableWarning
              spellCheck={editable}
              onInput={onDirty}
              onBlur={(event) => commitText("bullet", index, event)}
            >
              {item}
            </li>
          ))}
        </ul>
      ) : null}

      {section.code ? (
        <pre>
          <code
            contentEditable={editable}
            suppressContentEditableWarning
            spellCheck={false}
            onInput={onDirty}
            onBlur={(event) => commitText("code", 0, event)}
          >
            {section.code}
          </code>
        </pre>
      ) : null}
    </section>
  );
}

function DocumentPane({
  sections,
  editable,
  paneRef,
  headingRefs,
  onScroll,
  onCommit,
  onDirty,
  onFocusSection,
  variant,
}) {
  const paneTestId = variant.includes("reader") ? "reader-pane" : "source-pane";
  const registerHeading = useCallback(
    (id, node) => {
      if (node) headingRefs.current.set(id, node);
      else headingRefs.current.delete(id);
    },
    [headingRefs],
  );

  return (
    <div
      ref={paneRef}
      className={`document-scroll ${variant}`}
      data-testid={paneTestId}
      onScroll={onScroll}
      onFocusCapture={(event) => {
        const section = event.target.closest?.("[data-section-id]");
        if (section) onFocusSection(section.dataset.sectionId);
      }}
    >
      <article className="document-page" aria-label={editable ? "Markdown 编辑区" : "Markdown 阅读区"}>
        {sections.map((section) => (
          <DocumentSection
            key={section.id}
            section={section}
            editable={editable}
            registerHeading={registerHeading}
            onCommit={onCommit}
            onDirty={onDirty}
          />
        ))}
      </article>
    </div>
  );
}

function ToolButton({ label, children, onClick, disabled = false, active = false, testId }) {
  return (
    <button
      className={`tool-button ${active ? "is-active" : ""}`}
      type="button"
      aria-label={label}
      title={label}
      onMouseDown={(event) => event.preventDefault()}
      onClick={onClick}
      disabled={disabled}
      data-testid={testId}
    >
      {children}
    </button>
  );
}

function OutlineNode({
  node,
  depth,
  collapsed,
  activeId,
  onToggle,
  onJump,
  onKeyDown,
}) {
  const hasChildren = node.children.length > 0;
  const isCollapsed = collapsed.has(node.id);
  const isActive = activeId === node.id;

  return (
    <div className="outline-node" role="none">
      <div
        className={`outline-row ${isActive ? "is-active" : ""}`}
        role="treeitem"
        tabIndex={isActive ? 0 : -1}
        aria-level={depth + 1}
        aria-current={isActive ? "location" : undefined}
        aria-expanded={hasChildren ? !isCollapsed : undefined}
        data-outline-row="true"
        data-outline-id={node.id}
        data-parent-id={node.parentId || ""}
        style={{ "--outline-depth": depth }}
        title={node.title}
        onClick={() => onJump(node.id)}
        onKeyDown={(event) => onKeyDown(event, node, hasChildren, isCollapsed)}
      >
        {hasChildren ? (
          <button
            className="outline-caret has-children"
            type="button"
            tabIndex={-1}
            aria-label={isCollapsed ? `展开 ${node.title}` : `折叠 ${node.title}`}
            onClick={(event) => {
              event.stopPropagation();
              onToggle(node.id);
            }}
          >
            {isCollapsed ? <CaretRight weight="bold" /> : <CaretDown weight="bold" />}
          </button>
        ) : (
          <span className="outline-caret" aria-hidden="true" />
        )}
        <span className="outline-title">{node.title}</span>
      </div>

      {hasChildren && !isCollapsed ? (
        <div role="group">
          {node.children.map((child) => (
            <OutlineNode
              key={child.id}
              node={child}
              depth={depth + 1}
              collapsed={collapsed}
              activeId={activeId}
              onToggle={onToggle}
              onJump={onJump}
              onKeyDown={onKeyDown}
            />
          ))}
        </div>
      ) : null}
    </div>
  );
}

export function App() {
  const [documents, setDocuments] = useState(INITIAL_DOCUMENTS);
  const [selectedDocumentId, setSelectedDocumentId] = useState(INITIAL_DOCUMENTS[0].id);
  const [mode, setMode] = useState("edit");
  const [activeId, setActiveId] = useState("resize-outline");
  const [outlineVisible, setOutlineVisible] = useState(() => readStoredBoolean("downleaf-outline-visible", true));
  const [outlineWidth, setOutlineWidth] = useState(() => readStoredNumber("downleaf-outline-width", DEFAULT_OUTLINE_WIDTH));
  const [collapsed, setCollapsed] = useState(() => readStoredSet("downleaf-outline-collapsed"));
  const [isResizing, setIsResizing] = useState(false);
  const [autoSave, setAutoSave] = useState(() => readStoredBoolean("downleaf-auto-save", true));
  const [toast, setToast] = useState("");
  const [appWidth, setAppWidth] = useState(1600);
  const [libraryVisible, setLibraryVisible] = useState(true);
  const [menuOpen, setMenuOpen] = useState(false);
  const [dialog, setDialog] = useState(null);
  const [closeIntent, setCloseIntent] = useState("close");
  const [saveName, setSaveName] = useState("未命名文稿.md");
  const [saveLocation, setSaveLocation] = useState("文稿");
  const [openPath, setOpenPath] = useState("~/Documents/项目说明.md");
  const [appClosed, setAppClosed] = useState(false);
  const [quitQueue, setQuitQueue] = useState([]);

  const appRef = useRef(null);
  const sourcePaneRef = useRef(null);
  const readerPaneRef = useRef(null);
  const sourceHeadingRefs = useRef(new Map());
  const readerHeadingRefs = useRef(new Map());
  const outlineListRef = useRef(null);
  const outlineFollowPausedUntil = useRef(0);
  const navigationLockUntil = useRef(0);
  const scrollSyncLock = useRef(false);
  const toastTimer = useRef(null);
  const autoSaveTimer = useRef(null);
  const untitledCounter = useRef(1);
  const menuRef = useRef(null);

  const selectedDocument = useMemo(
    () => documents.find((document) => document.id === selectedDocumentId) || documents[0] || null,
    [documents, selectedDocumentId],
  );
  const sections = selectedDocument?.sections || [];
  const dirty = Boolean(selectedDocument?.dirty);

  const outlineTree = useMemo(() => buildOutlineTree(sections), [sections]);
  const maximumOutlineWidth = Math.min(MAX_OUTLINE_WIDTH, Math.max(MIN_OUTLINE_WIDTH, appWidth * 0.4));
  const effectiveOutlineWidth = clamp(outlineWidth, MIN_OUTLINE_WIDTH, maximumOutlineWidth);
  const outlineFits = appWidth >= 900;
  const showOutline = outlineVisible && outlineFits;

  const documentText = useMemo(
    () =>
      sections
        .flatMap((section) => [
          section.title,
          ...(section.paragraphs || []),
          ...(section.bullets || []),
          section.quote || "",
          section.code || "",
        ])
        .join("\n"),
    [sections],
  );

  const characterCount = documentText.replace(/\s/g, "").length;
  const latinWordCount = documentText.match(/[A-Za-z0-9]+/g)?.length || 0;
  const cjkCount = documentText.match(/[\u3400-\u9fff]/g)?.length || 0;
  const wordCount = latinWordCount + cjkCount;

  const showToast = useCallback((message) => {
    setToast(message);
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(""), 1800);
  }, []);

  useEffect(() => {
    const observer = new ResizeObserver(([entry]) => {
      setAppWidth(entry.contentRect.width);
    });
    if (appRef.current) observer.observe(appRef.current);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      const pane = sourcePaneRef.current;
      const heading = sourceHeadingRefs.current.get("resize-outline");
      if (!pane || !heading) return;
      const paneTop = pane.getBoundingClientRect().top;
      const headingTop = heading.getBoundingClientRect().top;
      pane.scrollTop += headingTop - paneTop - Math.min(150, pane.clientHeight * 0.17);
      setActiveId("resize-outline");
    }, 80);

    return () => window.clearTimeout(timer);
  }, []);

  useEffect(() => {
    try {
      window.localStorage.setItem("downleaf-outline-visible", String(outlineVisible));
    } catch {
      // Local persistence is a progressive enhancement in the prototype.
    }
  }, [outlineVisible]);

  useEffect(() => {
    try {
      window.localStorage.setItem("downleaf-outline-width", String(Math.round(outlineWidth)));
    } catch {
      // Local persistence is a progressive enhancement in the prototype.
    }
  }, [outlineWidth]);

  useEffect(() => {
    try {
      window.localStorage.setItem("downleaf-outline-collapsed", JSON.stringify([...collapsed]));
    } catch {
      // Local persistence is a progressive enhancement in the prototype.
    }
  }, [collapsed]);

  useEffect(() => {
    try {
      window.localStorage.setItem("downleaf-auto-save", String(autoSave));
    } catch {
      // Local persistence is a progressive enhancement in the prototype.
    }
  }, [autoSave]);

  useEffect(() => {
    sourceHeadingRefs.current.clear();
    readerHeadingRefs.current.clear();
    const firstSectionId = selectedDocument?.sections[0]?.id || "";
    setActiveId(firstSectionId);
    window.requestAnimationFrame(() => {
      if (sourcePaneRef.current) sourcePaneRef.current.scrollTop = 0;
      if (readerPaneRef.current) readerPaneRef.current.scrollTop = 0;
    });
  }, [selectedDocumentId]);

  useEffect(() => {
    if (appClosed) return undefined;
    const hasUnsavedDocument = documents.some((document) => document.isBuffer || document.dirty);
    if (!hasUnsavedDocument) return undefined;

    const handleBeforeUnload = (event) => {
      event.preventDefault();
      event.returnValue = "";
    };

    window.addEventListener("beforeunload", handleBeforeUnload);
    return () => window.removeEventListener("beforeunload", handleBeforeUnload);
  }, [appClosed, documents]);

  useEffect(() => {
    if (outlineWidth > maximumOutlineWidth) setOutlineWidth(maximumOutlineWidth);
  }, [maximumOutlineWidth, outlineWidth]);

  useEffect(() => {
    if (!menuOpen) return undefined;

    const handlePointerDown = (event) => {
      if (!menuRef.current?.contains(event.target)) setMenuOpen(false);
    };
    const handleEscape = (event) => {
      if (event.key === "Escape") setMenuOpen(false);
    };

    document.addEventListener("pointerdown", handlePointerDown);
    document.addEventListener("keydown", handleEscape);
    return () => {
      document.removeEventListener("pointerdown", handlePointerDown);
      document.removeEventListener("keydown", handleEscape);
    };
  }, [menuOpen]);

  useEffect(() => () => {
    window.clearTimeout(toastTimer.current);
    window.clearTimeout(autoSaveTimer.current);
  }, []);

  const commitSectionText = useCallback((sectionId, kind, index, value) => {
    setDocuments((current) =>
      current.map((document) => {
        if (document.id !== selectedDocumentId) return document;

        const nextSections = document.sections.map((section) => {
          if (section.id !== sectionId) return section;

          if (kind === "title") return { ...section, title: value };
          if (kind === "paragraph") {
            const paragraphs = [...(section.paragraphs || [])];
            paragraphs[index] = value;
            return { ...section, paragraphs };
          }
          if (kind === "bullet") {
            const bullets = [...(section.bullets || [])];
            bullets[index] = value;
            return { ...section, bullets };
          }
          if (kind === "quote") return { ...section, quote: value };
          if (kind === "code") return { ...section, code: value };
          return section;
        });

        return { ...document, sections: nextSections };
      }),
    );
  }, [selectedDocumentId]);

  const markDirty = useCallback(() => {
    window.clearTimeout(autoSaveTimer.current);
    setDocuments((current) =>
      current.map((document) => (
        document.id === selectedDocumentId
          ? { ...document, dirty: true, saveState: document.isBuffer ? "buffer" : "pending" }
          : document
      )),
    );

    if (!autoSave) return;

    autoSaveTimer.current = window.setTimeout(() => {
      setDocuments((current) =>
        current.map((document) => {
          if (document.id !== selectedDocumentId || document.isBuffer || !document.path) return document;
          return { ...document, dirty: false, meta: "刚刚", saveState: "auto" };
        }),
      );
    }, 650);
  }, [autoSave, selectedDocumentId]);

  const updateActiveFromPane = useCallback((pane, headingMap) => {
    if (!pane) return;
    const marker = pane.getBoundingClientRect().top + pane.clientHeight * 0.25;
    let currentId = sections[0]?.id;

    for (const section of sections) {
      const heading = headingMap.current.get(section.id);
      if (!heading) continue;
      if (heading.getBoundingClientRect().top <= marker + 2) currentId = section.id;
      else break;
    }

    if (currentId) setActiveId(currentId);
  }, [sections]);

  const syncPaneScroll = useCallback((fromPane, toPane) => {
    if (!fromPane || !toPane || scrollSyncLock.current) return;
    const maxFrom = Math.max(1, fromPane.scrollHeight - fromPane.clientHeight);
    const maxTo = Math.max(0, toPane.scrollHeight - toPane.clientHeight);
    const ratio = fromPane.scrollTop / maxFrom;
    scrollSyncLock.current = true;
    toPane.scrollTop = ratio * maxTo;
    window.requestAnimationFrame(() => {
      scrollSyncLock.current = false;
    });
  }, []);

  const handleSourceScroll = useCallback(() => {
    if (Date.now() >= navigationLockUntil.current) {
      updateActiveFromPane(sourcePaneRef.current, sourceHeadingRefs);
    }
    if (mode === "split") syncPaneScroll(sourcePaneRef.current, readerPaneRef.current);
  }, [mode, syncPaneScroll, updateActiveFromPane]);

  const handleReaderScroll = useCallback(() => {
    if (mode === "read" && Date.now() >= navigationLockUntil.current) {
      updateActiveFromPane(readerPaneRef.current, readerHeadingRefs);
    }
    if (mode === "split" && !scrollSyncLock.current) {
      if (Date.now() >= navigationLockUntil.current) {
        updateActiveFromPane(readerPaneRef.current, readerHeadingRefs);
      }
      syncPaneScroll(readerPaneRef.current, sourcePaneRef.current);
    }
  }, [mode, syncPaneScroll, updateActiveFromPane]);

  useEffect(() => {
    const followActiveItem = () => {
      if (!showOutline || !outlineListRef.current) return;
      const remainingPause = outlineFollowPausedUntil.current - Date.now();
      if (remainingPause > 0) {
        const timer = window.setTimeout(followActiveItem, remainingPause + 20);
        return () => window.clearTimeout(timer);
      }
      const activeRow = outlineListRef.current.querySelector(`[data-outline-id="${activeId}"]`);
      activeRow?.scrollIntoView({ block: "nearest", behavior: "smooth" });
      return undefined;
    };

    return followActiveItem();
  }, [activeId, showOutline]);

  const jumpToSection = useCallback((sectionId) => {
    navigationLockUntil.current = Date.now() + 850;
    const useReader = mode === "read";
    const pane = useReader ? readerPaneRef.current : sourcePaneRef.current;
    const heading = (useReader ? readerHeadingRefs : sourceHeadingRefs).current.get(sectionId);

    if (pane && heading) {
      const paneTop = pane.getBoundingClientRect().top;
      const headingTop = heading.getBoundingClientRect().top;
      pane.scrollTo({ top: pane.scrollTop + headingTop - paneTop - 64, behavior: "smooth" });
      if (!useReader) window.setTimeout(() => heading.focus({ preventScroll: true }), 280);
    }

    if (mode === "split") {
      const secondaryHeading = readerHeadingRefs.current.get(sectionId);
      const secondaryPane = readerPaneRef.current;
      if (secondaryPane && secondaryHeading) {
        const paneTop = secondaryPane.getBoundingClientRect().top;
        const headingTop = secondaryHeading.getBoundingClientRect().top;
        secondaryPane.scrollTo({ top: secondaryPane.scrollTop + headingTop - paneTop - 64, behavior: "smooth" });
      }
    }

    setActiveId(sectionId);
  }, [mode]);

  const toggleCollapsed = useCallback((sectionId) => {
    setCollapsed((current) => {
      const next = new Set(current);
      if (next.has(sectionId)) next.delete(sectionId);
      else next.add(sectionId);
      return next;
    });
  }, []);

  const handleOutlineKeyDown = useCallback((event, node, hasChildren, isCollapsed) => {
    const list = outlineListRef.current;
    if (!list) return;
    const rows = [...list.querySelectorAll('[data-outline-row="true"]')];
    const currentIndex = rows.indexOf(event.currentTarget);

    const focusAt = (index) => {
      const target = rows[clamp(index, 0, rows.length - 1)];
      target?.focus();
    };

    if (event.key === "ArrowDown") {
      event.preventDefault();
      focusAt(currentIndex + 1);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      focusAt(currentIndex - 1);
    } else if (event.key === "Home") {
      event.preventDefault();
      focusAt(0);
    } else if (event.key === "End") {
      event.preventDefault();
      focusAt(rows.length - 1);
    } else if (event.key === "Enter") {
      event.preventDefault();
      jumpToSection(node.id);
    } else if (event.key === "ArrowRight") {
      event.preventDefault();
      if (hasChildren && isCollapsed) toggleCollapsed(node.id);
      else list.querySelector(`[data-parent-id="${node.id}"]`)?.focus();
    } else if (event.key === "ArrowLeft") {
      event.preventDefault();
      if (hasChildren && !isCollapsed) toggleCollapsed(node.id);
      else if (node.parentId) list.querySelector(`[data-outline-id="${node.parentId}"]`)?.focus();
    }
  }, [jumpToSection, toggleCollapsed]);

  const handleResizeStart = useCallback((event) => {
    if (!outlineFits) return;
    event.preventDefault();
    const shellRight = appRef.current.getBoundingClientRect().right;
    const widthBeforeDrag = effectiveOutlineWidth;
    let lastDesiredWidth = effectiveOutlineWidth;
    setIsResizing(true);

    const handleMove = (moveEvent) => {
      lastDesiredWidth = shellRight - moveEvent.clientX;
      if (lastDesiredWidth >= MIN_OUTLINE_WIDTH - 24) {
        setOutlineWidth(clamp(lastDesiredWidth, MIN_OUTLINE_WIDTH, maximumOutlineWidth));
      }
    };

    const handleUp = () => {
      document.removeEventListener("pointermove", handleMove);
      document.removeEventListener("pointerup", handleUp);
      document.body.classList.remove("is-resizing-outline");
      setIsResizing(false);
      if (lastDesiredWidth < MIN_OUTLINE_WIDTH - 24) {
        setOutlineWidth(widthBeforeDrag);
        setOutlineVisible(false);
        showToast("大纲已收起 · ⌥⌘O 可重新打开");
      }
    };

    document.body.classList.add("is-resizing-outline");
    document.addEventListener("pointermove", handleMove);
    document.addEventListener("pointerup", handleUp);
  }, [effectiveOutlineWidth, maximumOutlineWidth, outlineFits, showToast]);

  const handleSplitterKeyDown = useCallback((event) => {
    let nextWidth = effectiveOutlineWidth;
    if (event.key === "ArrowLeft") nextWidth += 16;
    else if (event.key === "ArrowRight") nextWidth -= 16;
    else if (event.key === "Home") nextWidth = MIN_OUTLINE_WIDTH;
    else if (event.key === "End") nextWidth = maximumOutlineWidth;
    else return;
    event.preventDefault();
    setOutlineWidth(clamp(nextWidth, MIN_OUTLINE_WIDTH, maximumOutlineWidth));
  }, [effectiveOutlineWidth, maximumOutlineWidth]);

  const changeMode = useCallback((nextMode) => {
    setMode(nextMode);
    showToast(nextMode === "edit" ? "编辑模式" : nextMode === "split" ? "左右分屏" : "阅读模式");
  }, [showToast]);

  const applyFormat = useCallback((command, label) => {
    if (mode === "read") return;
    document.execCommand(command, false);
    markDirty();
    showToast(`${label}已应用`);
  }, [markDirty, mode, showToast]);

  const flushPendingAutoSave = useCallback((documentId = selectedDocumentId) => {
    window.clearTimeout(autoSaveTimer.current);
    if (!autoSave || !documentId) return;

    setDocuments((current) =>
      current.map((document) => (
        document.id === documentId && document.path && !document.isBuffer && document.dirty
          ? { ...document, dirty: false, meta: "刚刚", saveState: "auto" }
          : document
      )),
    );
  }, [autoSave, selectedDocumentId]);

  const createBufferedDocument = useCallback(() => {
    const ordinal = untitledCounter.current;
    untitledCounter.current += 1;
    const id = `untitled-${Date.now()}-${ordinal}`;
    const name = ordinal === 1 ? "未命名文稿" : `未命名文稿 ${ordinal}`;
    const nextDocument = {
      id,
      name,
      meta: "缓冲区",
      path: null,
      sections: createBlankSections(id),
      dirty: false,
      isBuffer: true,
      saveState: "buffer",
    };

    flushPendingAutoSave();
    setDocuments((current) => [nextDocument, ...current]);
    setSelectedDocumentId(id);
    setMode("edit");
    setDialog(null);
    setMenuOpen(false);
    showToast("未命名文稿已暂存于缓冲区");
  }, [flushPendingAutoSave, showToast]);

  const handleDocumentSelect = useCallback((documentId) => {
    const document = documents.find((item) => item.id === documentId);
    if (!document) return;
    flushPendingAutoSave();
    setSelectedDocumentId(documentId);
    showToast(document.isBuffer ? "已切换到缓冲文稿" : `已打开 ${document.name}`);
  }, [documents, flushPendingAutoSave, showToast]);

  const finishQuitStep = useCallback((documentId, discardDocument = false) => {
    const remainingQueue = quitQueue.filter((id) => id !== documentId);
    const remainingDocuments = discardDocument
      ? documents.filter((document) => document.id !== documentId)
      : documents;

    if (discardDocument) setDocuments(remainingDocuments);

    if (remainingQueue.length > 0) {
      setQuitQueue(remainingQueue);
      setSelectedDocumentId(remainingQueue[0]);
      setDialog("close");
      return;
    }

    setQuitQueue([]);
    setDialog(null);
    if (discardDocument) setSelectedDocumentId(remainingDocuments[0]?.id || "");
    setAppClosed(true);
  }, [documents, quitQueue]);

  const finishClose = useCallback((documentId, intent, discardOnQuit = false) => {
    setDialog(null);

    if (intent === "quit") {
      finishQuitStep(documentId, discardOnQuit);
      return;
    }

    const currentIndex = documents.findIndex((document) => document.id === documentId);
    const remainingDocuments = documents.filter((document) => document.id !== documentId);
    setDocuments(remainingDocuments);

    if (selectedDocumentId === documentId) {
      const nextDocument = remainingDocuments[Math.min(Math.max(currentIndex, 0), remainingDocuments.length - 1)];
      setSelectedDocumentId(nextDocument?.id || "");
    }

    showToast("文稿已关闭");
  }, [documents, finishQuitStep, selectedDocumentId, showToast]);

  const openSaveDialog = useCallback((intent = "save") => {
    if (!selectedDocument) return;
    setCloseIntent(intent);
    setSaveName(ensureMarkdownExtension(selectedDocument.name));
    setSaveLocation("文稿");
    setDialog("save");
    setMenuOpen(false);
  }, [selectedDocument]);

  const saveCurrentDocument = useCallback((intent = "save") => {
    if (!selectedDocument) return;
    window.clearTimeout(autoSaveTimer.current);

    if (selectedDocument.isBuffer || !selectedDocument.path) {
      openSaveDialog(intent);
      return;
    }

    setDocuments((current) =>
      current.map((document) => (
        document.id === selectedDocument.id
          ? { ...document, dirty: false, meta: "刚刚", saveState: "manual" }
          : document
      )),
    );

    if (intent === "close" || intent === "quit") {
      finishClose(selectedDocument.id, intent);
    } else {
      setDialog(null);
      showToast("已保存到原路径");
    }
  }, [finishClose, openSaveDialog, selectedDocument, showToast]);

  const requestCloseCurrent = useCallback((intent = "close") => {
    window.clearTimeout(autoSaveTimer.current);

    if (intent === "quit") {
      const documentsNeedingDecision = documents.filter((document) => (
        document.isBuffer || (document.dirty && !autoSave)
      ));

      if (autoSave) {
        setDocuments((current) =>
          current.map((document) => (
            document.dirty && document.path && !document.isBuffer
              ? { ...document, dirty: false, meta: "刚刚", saveState: "auto" }
              : document
          )),
        );
      }

      if (documentsNeedingDecision.length === 0) {
        setDialog(null);
        setMenuOpen(false);
        setAppClosed(true);
        return;
      }

      const nextQueue = documentsNeedingDecision.map((document) => document.id);
      setQuitQueue(nextQueue);
      setSelectedDocumentId(nextQueue[0]);
      setCloseIntent("quit");
      setDialog("close");
      setMenuOpen(false);
      return;
    }

    if (!selectedDocument) return;

    const needsConfirmation = selectedDocument.isBuffer || (selectedDocument.dirty && !autoSave);
    if (needsConfirmation) {
      setCloseIntent(intent);
      setDialog("close");
      setMenuOpen(false);
      return;
    }

    if (selectedDocument.dirty && autoSave && selectedDocument.path) {
      setDocuments((current) =>
        current.map((document) => (
          document.id === selectedDocument.id
            ? { ...document, dirty: false, meta: "刚刚", saveState: "auto" }
            : document
        )),
      );
    }

    finishClose(selectedDocument.id, intent);
  }, [autoSave, documents, finishClose, selectedDocument]);

  const confirmSaveLocation = useCallback(() => {
    if (!selectedDocument) return;
    const normalizedName = ensureMarkdownExtension(saveName);
    const directory = saveLocation === "桌面" ? "Desktop" : saveLocation === "下载" ? "Downloads" : "Documents";
    const nextPath = `~/${directory}/${normalizedName}`;

    setDocuments((current) =>
      current.map((document) => (
        document.id === selectedDocument.id
          ? {
            ...document,
            name: normalizedName,
            path: nextPath,
            meta: "刚刚",
            dirty: false,
            isBuffer: false,
            saveState: "manual",
          }
          : document
      )),
    );

    setDialog(null);
    if (closeIntent === "close" || closeIntent === "quit") {
      finishClose(selectedDocument.id, closeIntent);
    } else {
      showToast(`已保存到${saveLocation}`);
    }
  }, [closeIntent, finishClose, saveLocation, saveName, selectedDocument, showToast]);

  const discardAndContinue = useCallback(() => {
    if (!selectedDocument) return;
    finishClose(selectedDocument.id, closeIntent, true);
  }, [closeIntent, finishClose, selectedDocument]);

  const cancelCloseDialog = useCallback(() => {
    setDialog(null);
    if (closeIntent === "quit") setQuitQueue([]);
  }, [closeIntent]);

  const openDocumentDialog = useCallback(() => {
    setOpenPath("~/Documents/项目说明.md");
    setDialog("open");
    setMenuOpen(false);
  }, []);

  const confirmOpenDocument = useCallback(() => {
    const normalizedPath = openPath.trim() || "~/Documents/项目说明.md";
    const name = fileNameFromPath(normalizedPath);
    const id = `opened-${Date.now()}`;
    const title = name.replace(/\.md$/i, "");
    const nextDocument = {
      id,
      name,
      meta: "刚刚",
      path: normalizedPath,
      sections: [
        {
          id: `${id}-title`,
          level: 1,
          title,
          paragraphs: [
            "这个 Markdown 文件通过现有路径直接打开，编辑内容会继续写回原文件。",
            autoSave ? "自动保存已开启，修改会在输入停顿后安全写入。" : "自动保存已关闭，关闭前会询问是否保存修改。",
          ],
        },
      ],
      dirty: false,
      isBuffer: false,
      saveState: "opened",
    };

    flushPendingAutoSave();
    setDocuments((current) => [nextDocument, ...current]);
    setSelectedDocumentId(id);
    setMode("edit");
    setDialog(null);
    showToast("已从路径打开 Markdown 文件");
  }, [autoSave, flushPendingAutoSave, openPath, showToast]);

  const openSettings = useCallback(() => {
    setDialog("settings");
    setMenuOpen(false);
  }, []);

  const toggleAutoSave = useCallback(() => {
    const next = !autoSave;
    setAutoSave(next);
    window.clearTimeout(autoSaveTimer.current);

    if (next) {
      setDocuments((current) =>
        current.map((document) => (
          document.dirty && document.path && !document.isBuffer
            ? { ...document, dirty: false, meta: "刚刚", saveState: "auto" }
            : document
        )),
      );
    }

    showToast(next ? "自动保存已开启" : "自动保存已关闭");
  }, [autoSave, showToast]);

  const runMenuCommand = useCallback((message, action) => {
    setMenuOpen(false);
    action?.();
    if (message) showToast(message);
  }, [showToast]);

  useEffect(() => {
    if (appClosed) return undefined;
    const handleKeyboard = (event) => {
      const key = event.key.toLowerCase();

      if (dialog && event.key === "Escape") {
        event.preventDefault();
        if (dialog === "close") cancelCloseDialog();
        else if (dialog === "save" && closeIntent !== "save") setDialog("close");
        else setDialog(null);
        return;
      }
      if (dialog) return;

      if (event.metaKey && event.altKey && key === "o") {
        event.preventDefault();
        setOutlineVisible((visible) => !visible);
      } else if (event.metaKey && event.altKey && key === "e") {
        event.preventDefault();
        setMode("split");
      } else if (event.metaKey && key === "e") {
        event.preventDefault();
        setMode((current) => (current === "read" ? "edit" : "read"));
      } else if (event.metaKey && key === "s") {
        event.preventDefault();
        saveCurrentDocument("save");
      } else if (event.metaKey && !event.altKey && key === "n") {
        event.preventDefault();
        createBufferedDocument();
      } else if (event.metaKey && !event.altKey && key === "o") {
        event.preventDefault();
        openDocumentDialog();
      } else if (event.metaKey && key === "w") {
        event.preventDefault();
        requestCloseCurrent("close");
      } else if (event.metaKey && key === "q") {
        event.preventDefault();
        requestCloseCurrent("quit");
      } else if (event.metaKey && key === "f") {
        event.preventDefault();
        showToast("查找当前文稿");
      } else if (event.metaKey && event.key === ",") {
        event.preventDefault();
        openSettings();
      }
    };

    window.addEventListener("keydown", handleKeyboard);
    return () => window.removeEventListener("keydown", handleKeyboard);
  }, [appClosed, cancelCloseDialog, closeIntent, createBufferedDocument, dialog, openDocumentDialog, openSettings, requestCloseCurrent, saveCurrentDocument, showToast]);

  const documentStatus = !selectedDocument
    ? "没有打开的文稿"
    : selectedDocument.isBuffer
      ? "暂存于缓冲区 · 关闭时选择位置"
      : dirty
        ? autoSave ? "正在自动保存…" : "已修改 · ⌘S 保存"
        : selectedDocument.saveState === "auto" ? "已自动保存" : "已保存到本机";

  if (appClosed) {
    return (
      <div className="prototype-stage">
        <section className="app-closed-state" aria-label="Downleaf 已关闭" data-testid="app-closed-state">
          <div className="app-closed-icon"><FileText weight="fill" /></div>
          <h1>Downleaf 已安全关闭</h1>
          <p>所有需要确认的文稿都已处理。</p>
          <button
            type="button"
            onClick={() => {
              setSelectedDocumentId((current) => (
                documents.some((document) => document.id === current) ? current : documents[0]?.id || ""
              ));
              setAppClosed(false);
            }}
          >
            重新打开
          </button>
        </section>
      </div>
    );
  }

  return (
    <div className="prototype-stage">
      <div
        ref={appRef}
        className={`app-window ${isResizing ? "is-resizing" : ""}`}
        role="application"
        aria-label="Downleaf 可交互原型"
        data-testid="app-shell"
      >
        {libraryVisible ? (
          <aside className="library-sidebar" aria-label="文稿列表">
            <div className="library-header">
              <button className="bare-icon-button" type="button" aria-label="收起文稿栏" title="收起文稿栏" onClick={() => setLibraryVisible(false)}>
                <CaretLeft weight="bold" />
              </button>
              <div className="library-title">文稿</div>
              <button
                className="add-document-button"
                type="button"
                aria-label="新建文稿"
                title="新建文稿"
                data-testid="new-document-button"
                onClick={createBufferedDocument}
              >
                <Plus weight="bold" />
              </button>
            </div>

            <div className="document-list">
              {documents.map((document) => (
                <button
                  key={document.id}
                  className={`document-list-item ${selectedDocumentId === document.id ? "is-selected" : ""}`}
                  type="button"
                  onClick={() => handleDocumentSelect(document.id)}
                >
                  <span className="document-list-name-row">
                    <span className="document-list-name">{document.name}</span>
                    {document.isBuffer || document.dirty ? <span className="document-list-dot" aria-label="尚未保存" /> : null}
                  </span>
                  <span className="document-list-meta">{document.meta}</span>
                </button>
              ))}
            </div>

          </aside>
        ) : null}

        <section className="workspace">
          <header className="document-header">
            {!libraryVisible ? (
              <button className="bare-icon-button reveal-library" type="button" aria-label="显示文稿栏" title="显示文稿栏" onClick={() => setLibraryVisible(true)}>
                <SidebarSimple />
              </button>
            ) : null}
            <FileText className="header-file-icon" weight="fill" />
            <div className="document-identity">
              <div className="document-title-row">
                <span className="document-title">{selectedDocument?.name || "没有打开的文稿"}</span>
                {dirty || selectedDocument?.isBuffer ? <span className="dirty-dot" aria-label="尚未保存" /> : null}
              </div>
              <div className="save-state" data-testid="document-save-state">
                {!dirty && selectedDocument && !selectedDocument.isBuffer ? <Check weight="bold" /> : null}
                <span>{documentStatus}</span>
              </div>
            </div>

            <div className="header-actions">
              <div className="mode-switcher" role="group" aria-label="阅读方式">
                <ToolButton label="编辑模式 ⌘E" active={mode === "edit"} onClick={() => changeMode("edit")} testId="mode-edit">
                  <PencilSimple />
                </ToolButton>
                <ToolButton label="左右分屏 ⌥⌘E" active={mode === "split"} onClick={() => changeMode("split")} testId="mode-split">
                  <Columns />
                </ToolButton>
                <ToolButton label="阅读模式 ⌘E" active={mode === "read"} onClick={() => changeMode("read")} testId="mode-read">
                  <Article />
                </ToolButton>
              </div>
              <ToolButton
                label={outlineVisible ? "隐藏大纲 ⌥⌘O" : "显示大纲 ⌥⌘O"}
                active={outlineVisible}
                onClick={() => {
                  if (!outlineFits) showToast("窗口变宽后可重新显示大纲");
                  else setOutlineVisible((visible) => !visible);
                }}
                testId="outline-toggle"
              >
                <SidebarSimple />
              </ToolButton>
              <div className="app-menu-anchor" ref={menuRef}>
                <button
                  className={`tool-button app-menu-trigger ${menuOpen ? "is-active" : ""}`}
                  type="button"
                  aria-label="更多命令"
                  aria-haspopup="menu"
                  aria-expanded={menuOpen}
                  title="更多命令"
                  data-testid="app-menu-trigger"
                  onClick={() => setMenuOpen((open) => !open)}
                >
                  <DotsThree weight="bold" />
                </button>
                {menuOpen ? (
                  <div className="app-command-menu" role="menu" aria-label="Downleaf 命令" data-testid="app-command-menu">
                    <button type="button" role="menuitem" onClick={() => runMenuCommand(null, createBufferedDocument)}>
                      <span>新建文稿</span><kbd>⌘N</kbd>
                    </button>
                    <button type="button" role="menuitem" onClick={() => runMenuCommand(null, openDocumentDialog)}>
                      <span>打开…</span><kbd>⌘O</kbd>
                    </button>
                    <button type="button" role="menuitem" onClick={() => runMenuCommand("最近打开的文稿")}>
                      <span>打开最近</span><kbd>›</kbd>
                    </button>
                    <div className="app-menu-separator" role="separator" />
                    <button type="button" role="menuitem" onClick={() => runMenuCommand(null, () => saveCurrentDocument("save"))}>
                      <span>保存</span><kbd>⌘S</kbd>
                    </button>
                    <button type="button" role="menuitem" onClick={() => runMenuCommand(null, () => requestCloseCurrent("close"))}>
                      <span>关闭文稿</span><kbd>⌘W</kbd>
                    </button>
                    <div className="app-menu-separator" role="separator" />
                    <button type="button" role="menuitem" onClick={() => runMenuCommand("查找当前文稿")}>
                      <span>查找</span><kbd>⌘F</kbd>
                    </button>
                    <button type="button" role="menuitem" onClick={() => runMenuCommand(null, () => setLibraryVisible((visible) => !visible))}>
                      <span>{libraryVisible ? "隐藏文稿栏" : "显示文稿栏"}</span><kbd>⌥⌘L</kbd>
                    </button>
                    <button type="button" role="menuitem" onClick={() => runMenuCommand(null, () => setOutlineVisible((visible) => !visible))}>
                      <span>{outlineVisible ? "隐藏大纲" : "显示大纲"}</span><kbd>⌥⌘O</kbd>
                    </button>
                    <div className="app-menu-separator" role="separator" />
                    <button type="button" role="menuitem" onClick={() => runMenuCommand("已准备导出 PDF")}>
                      <span>导出 PDF…</span>
                    </button>
                    <button type="button" role="menuitem" onClick={() => runMenuCommand(null, openSettings)}>
                      <span>偏好设置…</span><kbd>⌘,</kbd>
                    </button>
                    <div className="app-menu-separator" role="separator" />
                    <button type="button" role="menuitem" onClick={() => runMenuCommand(null, () => requestCloseCurrent("quit"))}>
                      <span>退出 Downleaf</span><kbd>⌘Q</kbd>
                    </button>
                  </div>
                ) : null}
              </div>
            </div>
          </header>

          <div className="format-toolbar" aria-label="格式工具栏">
            <ToolButton label="撤销" onClick={() => document.execCommand("undo")} disabled={mode === "read"}><ArrowCounterClockwise /></ToolButton>
            <ToolButton label="重做" onClick={() => document.execCommand("redo")} disabled={mode === "read"}><ArrowClockwise /></ToolButton>
            <span className="toolbar-divider" />
            <button className="text-control" type="button" disabled={mode === "read"} onClick={() => showToast("段落样式：正文")}>正文 <CaretDown weight="bold" /></button>
            <button className="text-control compact" type="button" disabled={mode === "read"} onClick={() => showToast("字号：15 px")}>15px <CaretDown weight="bold" /></button>
            <span className="toolbar-divider" />
            <ToolButton label="粗体 ⌘B" onClick={() => applyFormat("bold", "粗体")} disabled={mode === "read"}><TextB weight="bold" /></ToolButton>
            <ToolButton label="斜体 ⌘I" onClick={() => applyFormat("italic", "斜体")} disabled={mode === "read"}><TextItalic /></ToolButton>
            <ToolButton label="删除线" onClick={() => applyFormat("strikeThrough", "删除线")} disabled={mode === "read"}><TextStrikethrough /></ToolButton>
            <ToolButton label="下划线" onClick={() => applyFormat("underline", "下划线")} disabled={mode === "read"}><TextUnderline /></ToolButton>
            <ToolButton label="标题" onClick={() => showToast("标题层级")} disabled={mode === "read"}><TextH /></ToolButton>
            <span className="toolbar-divider" />
            <ToolButton label="文字颜色" onClick={() => showToast("文字颜色")} disabled={mode === "read"}><PaintBrush /></ToolButton>
            <ToolButton label="任务列表" onClick={() => showToast("任务列表已插入")} disabled={mode === "read"}><CheckSquare /></ToolButton>
            <ToolButton label="链接" onClick={() => showToast("输入链接地址")} disabled={mode === "read"}><LinkSimple /></ToolButton>
            <ToolButton label="引用" onClick={() => showToast("引用块已插入")} disabled={mode === "read"}><Quotes weight="fill" /></ToolButton>
            <ToolButton label="分隔线" onClick={() => showToast("分隔线已插入")} disabled={mode === "read"}><Minus /></ToolButton>
            <ToolButton label="图片" onClick={() => showToast("选择本地图片")} disabled={mode === "read"}><ImageSquare /></ToolButton>
            <ToolButton label="代码块" onClick={() => showToast("代码块已插入")} disabled={mode === "read"}><Code /></ToolButton>
          </div>

          <div className={`document-layout mode-${mode} ${showOutline ? "has-outline" : ""}`}>
            <main className="content-region">
              {!selectedDocument ? (
                <div className="empty-document-state" data-testid="empty-document-state">
                  <FileText weight="thin" />
                  <h2>没有打开的文稿</h2>
                  <p>新建一份缓冲文稿，或从已有路径打开 Markdown 文件。</p>
                  <div>
                    <button type="button" className="dialog-button primary" onClick={createBufferedDocument}>新建文稿</button>
                    <button type="button" className="dialog-button" onClick={openDocumentDialog}>打开…</button>
                  </div>
                </div>
              ) : (
                <>
                  {mode === "edit" ? (
                    <DocumentPane
                      key={`${selectedDocumentId}-edit`}
                      sections={sections}
                      editable
                      paneRef={sourcePaneRef}
                      headingRefs={sourceHeadingRefs}
                      onScroll={handleSourceScroll}
                      onCommit={commitSectionText}
                      onDirty={markDirty}
                      onFocusSection={setActiveId}
                      variant="source-pane"
                    />
                  ) : null}

                  {mode === "split" ? (
                    <div className="split-layout">
                      <DocumentPane
                        key={`${selectedDocumentId}-split-source`}
                        sections={sections}
                        editable
                        paneRef={sourcePaneRef}
                        headingRefs={sourceHeadingRefs}
                        onScroll={handleSourceScroll}
                        onCommit={commitSectionText}
                        onDirty={markDirty}
                        onFocusSection={setActiveId}
                        variant="source-pane split-source"
                      />
                      <div className="split-divider" aria-hidden="true" />
                      <DocumentPane
                        key={`${selectedDocumentId}-split-reader`}
                        sections={sections}
                        editable={false}
                        paneRef={readerPaneRef}
                        headingRefs={readerHeadingRefs}
                        onScroll={handleReaderScroll}
                        onCommit={() => {}}
                        onDirty={() => {}}
                        onFocusSection={setActiveId}
                        variant="reader-pane split-reader"
                      />
                    </div>
                  ) : null}

                  {mode === "read" ? (
                  <DocumentPane
                    key={`${selectedDocumentId}-read`}
                    sections={sections}
                    editable={false}
                    paneRef={readerPaneRef}
                    headingRefs={readerHeadingRefs}
                    onScroll={handleReaderScroll}
                    onCommit={() => {}}
                    onDirty={() => {}}
                    onFocusSection={setActiveId}
                    variant="reader-pane"
                  />
                  ) : null}
                </>
              )}
            </main>

            {showOutline && selectedDocument ? (
              <>
                <div
                  className="outline-resizer"
                  role="separator"
                  aria-label="调整大纲宽度"
                  aria-orientation="vertical"
                  aria-valuemin={MIN_OUTLINE_WIDTH}
                  aria-valuemax={Math.round(maximumOutlineWidth)}
                  aria-valuenow={Math.round(effectiveOutlineWidth)}
                  tabIndex={0}
                  data-testid="outline-resizer"
                  onPointerDown={handleResizeStart}
                  onDoubleClick={() => {
                    setOutlineWidth(DEFAULT_OUTLINE_WIDTH);
                    showToast("大纲宽度已恢复默认");
                  }}
                  onKeyDown={handleSplitterKeyDown}
                />
                <aside
                  className="outline-pane"
                  aria-label="快速大纲"
                  data-testid="outline-pane"
                  style={{ width: `${effectiveOutlineWidth}px` }}
                >
                  <div className="outline-header">
                    <div className="outline-heading-row">
                      <h2>大纲</h2>
                      <span>{sections.length} 个标题</span>
                    </div>
                    <p title={selectedDocument.name}>{selectedDocument.name.replace(/\.md$/i, "")}</p>
                  </div>
                  <div
                    ref={outlineListRef}
                    className="outline-list"
                    role="tree"
                    aria-label="文档标题"
                    onWheel={() => {
                      outlineFollowPausedUntil.current = Date.now() + 1400;
                    }}
                    onPointerDown={() => {
                      outlineFollowPausedUntil.current = Date.now() + 1400;
                    }}
                  >
                    {outlineTree.map((node) => (
                      <OutlineNode
                        key={node.id}
                        node={node}
                        depth={0}
                        collapsed={collapsed}
                        activeId={activeId}
                        onToggle={toggleCollapsed}
                        onJump={jumpToSection}
                        onKeyDown={handleOutlineKeyDown}
                      />
                    ))}
                  </div>
                  <div className="outline-footer">
                    <span className="outline-width-readout">{Math.round(effectiveOutlineWidth)} px</span>
                    <button type="button" onClick={() => setOutlineVisible(false)}>⌥⌘O 隐藏</button>
                  </div>
                </aside>
              </>
            ) : null}
          </div>

          <footer className="status-bar">
            <div className="status-left">
              <span className={`status-ready ${selectedDocument?.isBuffer ? "is-buffer" : ""}`}>
                {selectedDocument?.isBuffer ? <FileText weight="fill" /> : <Check weight="bold" />}
                {selectedDocument?.isBuffer ? "缓冲文稿" : selectedDocument ? "本地文件" : "等待打开"}
              </span>
              <span>{wordCount.toLocaleString("zh-CN")} 字</span>
              <span>{characterCount.toLocaleString("zh-CN")} 字符</span>
            </div>
            <div className="status-right">
              <span>{mode === "edit" ? "编辑" : mode === "split" ? "分屏" : "阅读"}</span>
              <span>UTF-8</span>
              <span>Ln 1, Col 1</span>
            </div>
          </footer>
        </section>

        {dialog ? (
          <div className="dialog-backdrop">
            {dialog === "close" && selectedDocument ? (
              <section
                className="document-dialog close-dialog"
                role="alertdialog"
                aria-modal="true"
                aria-labelledby="close-dialog-title"
                aria-describedby="close-dialog-description"
                data-testid="close-document-dialog"
              >
                <div className="dialog-file-icon"><FileText weight="fill" /></div>
                <div className="dialog-copy">
                  <h2 id="close-dialog-title">
                    {closeIntent === "quit" ? `退出前要保存“${selectedDocument.name}”吗？` : `要保存“${selectedDocument.name}”吗？`}
                  </h2>
                  <p id="close-dialog-description">
                    {selectedDocument.isBuffer
                      ? `${closeIntent === "quit" ? "退出不会静默丢弃它。" : ""}这份文稿目前只在恢复缓冲区中。保存后，你可以选择文件名和位置。`
                      : `${closeIntent === "quit" ? "退出前需要处理这份文稿。" : ""}自动保存已关闭，这份文稿还有尚未写回原路径的修改。`}
                  </p>
                </div>
                <div className="dialog-actions three-actions">
                  <button type="button" className="dialog-button" onClick={cancelCloseDialog} data-testid="close-cancel-button">取消</button>
                  <button type="button" className="dialog-button danger" onClick={discardAndContinue} data-testid="close-discard-button">不保存</button>
                  <button type="button" className="dialog-button primary" onClick={() => saveCurrentDocument(closeIntent)} data-testid="close-save-button">
                    {selectedDocument.isBuffer ? "保存…" : "保存"}
                  </button>
                </div>
              </section>
            ) : null}

            {dialog === "save" && selectedDocument ? (
              <form
                className="document-dialog save-dialog"
                role="dialog"
                aria-modal="true"
                aria-labelledby="save-dialog-title"
                data-testid="save-location-dialog"
                onSubmit={(event) => {
                  event.preventDefault();
                  confirmSaveLocation();
                }}
              >
                <div className="dialog-copy full-width">
                  <span className="dialog-eyebrow">首次保存</span>
                  <h2 id="save-dialog-title">选择文件名和位置</h2>
                  <p>在保存之前，这份文稿会继续安全地保留在恢复缓冲区。</p>
                </div>
                <label className="dialog-field full-width">
                  <span>名称</span>
                  <input
                    type="text"
                    value={saveName}
                    autoFocus
                    data-testid="save-name-input"
                    onChange={(event) => setSaveName(event.target.value)}
                  />
                </label>
                <label className="dialog-field full-width">
                  <span>位置</span>
                  <select value={saveLocation} data-testid="save-location-select" onChange={(event) => setSaveLocation(event.target.value)}>
                    <option>文稿</option>
                    <option>桌面</option>
                    <option>下载</option>
                  </select>
                </label>
                <div className="save-path-preview full-width">
                  ~/{saveLocation === "桌面" ? "Desktop" : saveLocation === "下载" ? "Downloads" : "Documents"}/{ensureMarkdownExtension(saveName)}
                </div>
                <div className="dialog-actions full-width">
                  <button type="button" className="dialog-button" onClick={() => setDialog(closeIntent === "save" ? null : "close")}>取消</button>
                  <button type="submit" className="dialog-button primary" data-testid="confirm-save-location-button">
                    {closeIntent === "close" ? "保存并关闭" : closeIntent === "quit" ? "保存并退出" : "保存"}
                  </button>
                </div>
              </form>
            ) : null}

            {dialog === "open" ? (
              <form
                className="document-dialog open-dialog"
                role="dialog"
                aria-modal="true"
                aria-labelledby="open-dialog-title"
                data-testid="open-document-dialog"
                onSubmit={(event) => {
                  event.preventDefault();
                  confirmOpenDocument();
                }}
              >
                <div className="dialog-copy full-width">
                  <span className="dialog-eyebrow">打开现有文件</span>
                  <h2 id="open-dialog-title">输入 Markdown 文件路径</h2>
                  <p>已有路径的文件会直接打开，并继续在原位置保存。</p>
                </div>
                <label className="dialog-field full-width">
                  <span>文件路径</span>
                  <input
                    type="text"
                    value={openPath}
                    autoFocus
                    data-testid="open-path-input"
                    onChange={(event) => setOpenPath(event.target.value)}
                  />
                </label>
                <div className="dialog-actions full-width">
                  <button type="button" className="dialog-button" onClick={() => setDialog(null)}>取消</button>
                  <button type="submit" className="dialog-button primary" data-testid="confirm-open-path-button">打开</button>
                </div>
              </form>
            ) : null}

            {dialog === "settings" ? (
              <section
                className="document-dialog settings-dialog"
                role="dialog"
                aria-modal="true"
                aria-labelledby="settings-dialog-title"
                data-testid="settings-dialog"
              >
                <div className="dialog-copy full-width">
                  <span className="dialog-eyebrow">通用</span>
                  <h2 id="settings-dialog-title">偏好设置</h2>
                </div>
                <div className="settings-row full-width">
                  <div>
                    <strong>自动保存</strong>
                    <p>已有路径的文件会在输入停顿后自动写回；未命名文稿只更新恢复缓冲，首次保存仍由你选择位置。</p>
                  </div>
                  <button
                    type="button"
                    className={`toggle-switch ${autoSave ? "is-on" : ""}`}
                    role="switch"
                    aria-checked={autoSave}
                    aria-label="自动保存"
                    data-testid="auto-save-switch"
                    onClick={toggleAutoSave}
                  >
                    <span />
                  </button>
                </div>
                <div className="settings-note full-width">
                  <Check weight="bold" /> 默认开启，设置会保存在这台 Mac 上。
                </div>
                <div className="dialog-actions full-width">
                  <button type="button" className="dialog-button primary" onClick={() => setDialog(null)}>完成</button>
                </div>
              </section>
            ) : null}
          </div>
        ) : null}

        {toast ? <div className="toast" role="status">{toast}</div> : null}
      </div>
    </div>
  );
}
