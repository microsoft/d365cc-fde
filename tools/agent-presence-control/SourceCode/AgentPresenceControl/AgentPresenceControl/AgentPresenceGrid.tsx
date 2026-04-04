import * as React from 'react';
import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import {
    makeStyles,
    mergeClasses as fluentMergeClasses,
    Input,
    Button,
    Spinner,
    Text,
    Badge,
    Menu,
    MenuTrigger,
    MenuPopover,
    MenuList,
    MenuItem,
} from '@fluentui/react-components';
import { PresenceIcon, resolvePresenceStatus, PRESENCE_LABELS, PresenceStatus } from './PresenceIcon';

/** Typed wrapper — avoids @typescript-eslint/no-unsafe-* on mergeClasses variadic args */
const cx = (...classes: string[]): string => (fluentMergeClasses as (...c: string[]) => string)(...classes);

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export interface IAgentStatusRecord {
    id:                  string;
    agentId:             string;
    agentName:           string;
    presenceId:          string;
    presenceName:        string;
    basePresenceStatus:  number;
    presenceStatus:      PresenceStatus;   // precomputed — avoids repeated resolvePresenceStatus calls
    isLoggedIn:          boolean;
    startTime:           Date | null;
}

export interface IPresenceOption {
    id:                 string;
    name:               string;
    basePresenceStatus: number;
    canUserSet:         boolean;
}

export interface IQueue {
    id:   string;
    name: string;
}

export interface IStatusHistoryEntry {
    presenceId:     string;
    presenceName:   string;
    presenceStatus: PresenceStatus;
    startTime:      Date;
    endTime:        Date | null;  // null = still active (open-ended)
    durationMs:     number;
}

interface IAgentHistory {
    entries:  IStatusHistoryEntry[];
    loading:  boolean;
    error:    string | null;
}

/** One day's data used by the history modal */
interface IHistoryDay {
    dateLabel: string;       // e.g. "Mon, 31 Mar 2026"
    dateKey:   string;       // YYYY-MM-DD for sorting
    entries:   IStatusHistoryEntry[];
    /** Total ms per presenceStatus for the summary bar */
    summary:   Map<PresenceStatus, { name: string; ms: number }>;
    totalMs:   number;
}

type SortColumn    = 'agentName' | 'presence';
type SortDirection = 'asc' | 'desc';
type GroupBy       = 'presence' | 'loggedIn' | null;

interface ISortState {
    column:    SortColumn;
    direction: SortDirection;
}

type GridRow =
    | { kind: 'group-header'; groupKey: string; label: string; count: number; presenceName: string; basePresenceStatus: number }
    | { kind: 'agent'; data: IAgentStatusRecord };

export interface IAgentPresenceGridProps {
    webAPI:  ComponentFramework.WebApi;
    userId?: string;
    width?:  number;
    height?: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const POLL_INTERVAL_MS        = 10_000;
const QUEUE_FETCH_CONCURRENCY = 5;       // max parallel queue-member HTTP requests
const ROW_HEIGHT              = 37;      // px — agent row (8px pad + 20px line + 8px pad + 1px border)
const GROUP_ROW_HEIGHT        = 33;      // px — group header row
const DETAIL_HEIGHT           = 260;     // px — expanded detail panel (includes history timeline)
const OVERSCAN                = 8;       // extra rows rendered above/below viewport

/**
 * OData query using confirmed field names from:
 * https://learn.microsoft.com/en-us/dynamics365/developer/reference/entities/msdyn_agentstatus
 * https://learn.microsoft.com/en-us/dynamics365/developer/reference/entities/msdyn_presence
 */
const ODATA_OPTIONS =
    '?$select=msdyn_agentstatusid,msdyn_isagentloggedin,msdyn_presencemodifiedon,msdyn_presencemodifiedonwithmilliseconds' +
    '&$expand=msdyn_agentid($select=systemuserid,fullname,applicationid,isdisabled)' +
    ',msdyn_currentpresenceid($select=msdyn_presenceid,msdyn_name,msdyn_basepresencestatus,msdyn_presencestatustext)';

const GROUP_BY_LABELS: Record<NonNullable<GroupBy>, string> = {
    presence: 'Presence',
    loggedIn: 'Logged In',
};

const STATUS_ORDER: PresenceStatus[] = [
    'available', 'busy', 'donotdisturb', 'berightback', 'away', 'offline', 'unknown',
];

// ─────────────────────────────────────────────────────────────────────────────
// Inline SVG icons
// ─────────────────────────────────────────────────────────────────────────────

const SearchIcon = (): React.ReactElement => (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
        <path d="M7 1a6 6 0 1 0 3.745 10.745l2.755 2.755.707-.707-2.755-2.755A6 6 0 0 0 7 1zm-5 6a5 5 0 1 1 10 0A5 5 0 0 1 2 7z" />
    </svg>
);

const ChevronDownIcon = (): React.ReactElement => (
    <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
        <path d="M2 4l4 4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
);

const ChevronRightIcon = (): React.ReactElement => (
    <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
        <path d="M4 2l4 4-4 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
);

const PencilIcon = (): React.ReactElement => (
    <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
        <path d="M13.23 1a2.6 2.6 0 0 1 1.84 4.44L4.5 16H1v-3.5L11.4 1.93A2.6 2.6 0 0 1 13.23 1zm0 1a1.6 1.6 0 0 0-1.14.47L3 11.59V15h3.41L15.53 5.9A1.6 1.6 0 0 0 13.23 2z"/>
    </svg>
);

const HistoryIcon = (): React.ReactElement => (
    <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
        <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zm0 1a6 6 0 1 1 0 12A6 6 0 0 1 8 2zm-.5 2v4.22l2.64 2.64.71-.7L8.5 7.56V4H7.5z"/>
    </svg>
);

const QueueIcon = (): React.ReactElement => (
    <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
        <path d="M1 2.5A1.5 1.5 0 0 1 2.5 1h3A1.5 1.5 0 0 1 7 2.5v3A1.5 1.5 0 0 1 5.5 7h-3A1.5 1.5 0 0 1 1 5.5v-3zm1.5-.5a.5.5 0 0 0-.5.5v3a.5.5 0 0 0 .5.5h3a.5.5 0 0 0 .5-.5v-3a.5.5 0 0 0-.5-.5h-3zm5.5.5A1.5 1.5 0 0 1 9.5 1h3A1.5 1.5 0 0 1 14 2.5v3A1.5 1.5 0 0 1 12.5 7h-3A1.5 1.5 0 0 1 8 5.5v-3zm1.5-.5a.5.5 0 0 0-.5.5v3a.5.5 0 0 0 .5.5h3a.5.5 0 0 0 .5-.5v-3a.5.5 0 0 0-.5-.5h-3zM1 9.5A1.5 1.5 0 0 1 2.5 8h3A1.5 1.5 0 0 1 7 9.5v3A1.5 1.5 0 0 1 5.5 14h-3A1.5 1.5 0 0 1 1 12.5v-3zm1.5-.5a.5.5 0 0 0-.5.5v3a.5.5 0 0 0 .5.5h3a.5.5 0 0 0 .5-.5v-3a.5.5 0 0 0-.5-.5h-3zm5.5.5A1.5 1.5 0 0 1 9.5 8h3A1.5 1.5 0 0 1 14 9.5v3A1.5 1.5 0 0 1 12.5 14h-3A1.5 1.5 0 0 1 8 12.5v-3zm1.5-.5a.5.5 0 0 0-.5.5v3a.5.5 0 0 0 .5.5h3a.5.5 0 0 0 .5-.5v-3a.5.5 0 0 0-.5-.5h-3z"/>
    </svg>
);

/** Simple flat grey refresh icon — no borders or embossing */
const RefreshIcon = ({ size = 14 }: { size?: number }): React.ReactElement => (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="#8a8886">
        <path d="M9 2a7 7 0 1 0 6.32 4h-1.9A5.25 5.25 0 1 1 9 3.75V2z" />
        <path d="M9 0v5l3.5-2.5L9 0z" />
    </svg>
);

// ─────────────────────────────────────────────────────────────────────────────
// Styles — pixel-perfect Dataverse grid
// Exact values sourced from Dataverse grid inspector:
//   row border:  #edebe9 | hover: #f3f2f1 | selected: #deecf9
//   header text: #605e5c | link:  #106ebe  | body text: #323130
// ─────────────────────────────────────────────────────────────────────────────

const useStyles = makeStyles({
    root: {
        display:         'flex',
        flexDirection:   'column',
        width:           '100%',
        height:          '100%',
        minHeight:       '300px',
        boxSizing:       'border-box',
        backgroundColor: '#ffffff',
        fontFamily:      '"Segoe UI", -apple-system, BlinkMacSystemFont, sans-serif',
        fontSize:        '13px',
        color:           '#323130',
        overflow:        'hidden',
    },

    // ── title / header bar ───────────────────────────────────────────────────
    headerBar: {
        display:      'flex',
        alignItems:   'center',
        padding:      '8px 16px',
        borderBottom: '1px solid #edebe9',
        gap:          '8px',
        flexWrap:     'wrap',
        minHeight:    '40px',
    },
    title: {
        fontWeight:  '600',
        fontSize:    '16px',
        color:       '#323130',
        lineHeight:  '22px',
    },
    headerRight: {
        display:    'flex',
        alignItems: 'center',
        gap:        '8px',
        marginLeft: 'auto',
    },
    lastUpdatedText: {
        fontSize: '11px',
        color:    '#a19f9d',
    },

    // ── status summary bar ───────────────────────────────────────────────────
    summaryBar: {
        display:         'flex',
        alignItems:      'center',
        flexWrap:        'wrap',
        gap:             '0 20px',
        padding:         '5px 16px',
        backgroundColor: '#faf9f8',
        borderBottom:    '1px solid #edebe9',
    },
    summaryTotal: {
        fontWeight:   '600',
        fontSize:     '12px',
        color:        '#605e5c',
        paddingRight: '16px',
        borderRight:  '1px solid #c8c6c4',
        marginRight:  '4px',
        lineHeight:   '22px',
        cursor:       'pointer',
        borderRadius: '4px',
        padding:      '2px 16px 2px 4px',
        ':hover': {
            color:           '#106ebe',
            backgroundColor: '#e1effa',
        },
    },
    summaryItem: {
        display:      'flex',
        alignItems:   'center',
        gap:          '4px',
        fontSize:     '12px',
        color:        '#605e5c',
        lineHeight:   '22px',
        cursor:       'pointer',
        padding:      '2px 6px',
        borderRadius: '4px',
        ':hover': {
            color:           '#106ebe',
            backgroundColor: '#e1effa',
        },
    },
    summaryItemActive: {
        color:           '#106ebe',
        backgroundColor: '#e1effa',
        fontWeight:      '600',
    },
    summaryCount: {
        fontWeight: '600',
        color:      'inherit',
        fontSize:   '12px',
    },

    // ── queue filter bar ──────────────────────────────────────────────────────
    queueBar: {
        display:         'flex',
        alignItems:      'center',
        flexWrap:        'wrap',
        gap:             '6px',
        padding:         '6px 16px',
        backgroundColor: '#f3f2f1',
        borderBottom:    '1px solid #edebe9',
    },
    queueBarLabel: {
        fontSize:   '11px',
        fontWeight: '600',
        color:      '#605e5c',
        textTransform: 'uppercase',
        letterSpacing: '0.4px',
        marginRight: '4px',
        whiteSpace: 'nowrap',
    },
    queuePill: {
        display:      'flex',
        alignItems:   'center',
        gap:          '4px',
        padding:      '2px 8px',
        borderRadius: '12px',
        border:       '1px solid #c8c6c4',
        backgroundColor: '#ffffff',
        fontSize:     '12px',
        color:        '#323130',
        cursor:       'pointer',
        whiteSpace:   'nowrap',
        ':hover': {
            borderColor:     '#0f6cbd',
            color:           '#0f6cbd',
        },
    },
    queuePillActive: {
        backgroundColor: '#0f6cbd',
        borderColor:     '#0f6cbd',
        color:           '#ffffff',
    },
    queuePillRemove: {
        background:   'none',
        border:       'none',
        cursor:       'pointer',
        padding:      '0 0 0 2px',
        color:        'inherit',
        display:      'inline-flex',
        alignItems:   'center',
        lineHeight:   '1',
        opacity:      '0.7',
        ':hover': { opacity: '1' },
    },
    queuePickerBtn: {
        display:      'flex',
        alignItems:   'center',
        gap:          '4px',
        padding:      '2px 10px',
        borderRadius: '12px',
        border:       '1px dashed #0f6cbd',
        backgroundColor: 'transparent',
        fontSize:     '12px',
        color:        '#0f6cbd',
        cursor:       'pointer',
        whiteSpace:   'nowrap',
        ':hover': { backgroundColor: '#e1effa' },
    },
    queueDropdown: {
        position:      'fixed',
        zIndex:        '2000',
        background:    '#ffffff',
        border:        '1px solid #c8c6c4',
        borderRadius:  '6px',
        boxShadow:     '0 4px 20px rgba(0,0,0,0.16)',
        width:         '300px',
        maxHeight:     '360px',
        display:       'flex',
        flexDirection: 'column',
        overflow:      'hidden',
    },
    queueDropdownSearch: {
        padding:      '8px',
        borderBottom: '1px solid #edebe9',
        flexShrink:   '0',
    },
    queueDropdownList: {
        overflowY:  'auto',
        flexGrow:   '1',
    },
    queueDropdownItem: {
        display:    'flex',
        alignItems: 'center',
        gap:        '8px',
        padding:    '8px 12px',
        fontSize:   '13px',
        color:      '#323130',
        cursor:     'pointer',
        ':hover': { backgroundColor: '#f3f2f1' },
    },
    queueDropdownItemChecked: {
        backgroundColor: '#e1effa',
        color:           '#0f6cbd',
    },
    queueDropdownEmpty: {
        padding:   '16px 12px',
        fontSize:  '12px',
        color:     '#a19f9d',
        textAlign: 'center',
    },

    // ── toolbar ──────────────────────────────────────────────────────────────
    toolbar: {
        display:         'flex',
        alignItems:      'center',
        flexWrap:        'wrap',
        gap:             '8px',
        padding:         '6px 16px',
        backgroundColor: '#ffffff',
        borderBottom:    '1px solid #edebe9',
    },
    searchInput: {
        minWidth: '200px',
        maxWidth: '300px',
        flex:     '1 1 auto',
    },
    toolbarRight: {
        display:    'flex',
        alignItems: 'center',
        gap:        '8px',
        marginLeft: 'auto',
    },
    toggleWrapper: {
        display:    'flex',
        alignItems: 'center',
        gap:        '6px',
        cursor:     'pointer',
        userSelect: 'none',
    },
    toggleLabel: {
        fontSize:   '12px',
        color:      '#605e5c',
        whiteSpace: 'nowrap',
    },
    toggleTrack: {
        position:      'relative',
        width:         '32px',
        height:        '18px',
        borderRadius:  '9px',
        background:    '#c8c6c4',
        transition:    'background 0.2s',
        flexShrink:    '0',
    },
    toggleTrackOn: {
        background: '#0f6cbd',
    },
    toggleThumb: {
        position:     'absolute',
        top:          '2px',
        left:         '2px',
        width:        '14px',
        height:       '14px',
        borderRadius: '50%',
        background:   '#ffffff',
        boxShadow:    '0 1px 3px rgba(0,0,0,0.25)',
        transition:   'left 0.2s',
    },
    toggleThumbOn: {
        left: '16px',
    },
    countText: {
        fontSize:   '12px',
        color:      '#a19f9d',
        whiteSpace: 'nowrap',
    },

    // ── table container ───────────────────────────────────────────────────────
    tableContainer: {
        flex:            '1 1 0',
        overflowY:       'auto',
        overflowX:       'hidden',   // horizontal scroll only when unavoidable
        backgroundColor: '#ffffff',
        width:           '100%',
        boxSizing:       'border-box',
    },
    table: {
        width:          '100%',
        tableLayout:    'fixed',     // columns share available width proportionally
        borderCollapse: 'collapse',
        fontSize:       '13px',
        color:          '#323130',
    },

    // ── thead ─────────────────────────────────────────────────────────────────
    thead: {
        position:        'sticky',
        top:             '0',
        zIndex:          '2',
        backgroundColor: '#ffffff',
    },
    th: {
        textAlign:     'left',
        fontWeight:    '600',
        fontSize:      '12px',
        color:         '#605e5c',
        padding:       '8px 12px',
        borderBottom:  '1px solid #c8c6c4',
        whiteSpace:    'nowrap',
        userSelect:    'none',
        cursor:        'pointer',
        lineHeight:    '20px',
        ':hover': {
            color:           '#323130',
            backgroundColor: '#f3f2f1',
        },
    },
    thSortActive: {
        color: '#323130',
    },
    thPresence: {
        width:     '80px',
        textAlign: 'center',
    },
    thContent: {
        display:    'flex',
        alignItems: 'center',
        gap:        '4px',
    },
    thSortIcon: {
        fontSize: '10px',
        color:    '#605e5c',
        opacity:  '0.7',
    },
    thSortIconActive: {
        color:   '#323130',
        opacity: '1',
    },

    // ── tbody rows ────────────────────────────────────────────────────────────
    tr: {
        borderBottom: '1px solid #edebe9',
        ':hover': {
            backgroundColor: '#f3f2f1',
        },
    },
    trSelected: {
        backgroundColor: '#deecf9',
        ':hover': {
            backgroundColor: '#c7e0f4',
        },
    },
    tdExpander: {
        width:     '32px',
        padding:   '0 0 0 8px',
        textAlign: 'center',
        verticalAlign: 'middle',
    },
    expanderBtn: {
        background:  'none',
        border:      'none',
        cursor:      'pointer',
        padding:     '2px',
        color:       '#605e5c',
        display:     'inline-flex',
        alignItems:  'center',
        borderRadius: '2px',
        ':hover': {
            color:           '#323130',
            backgroundColor: '#edebe9',
        },
    },
    trDetail: {
        borderBottom: '1px solid #edebe9',
    },
    tdDetail: {
        padding:    '0',
        background: '#faf9f8',
    },
    detailPanel: {
        padding:    '12px 16px 12px 48px',
        display:    'flex',
        flexWrap:   'wrap',
        gap:        '24px',
    },
    detailField: {
        display:       'flex',
        flexDirection: 'column',
        gap:           '2px',
        minWidth:      '120px',
    },
    detailLabel: {
        fontSize:   '11px',
        fontWeight: '600',
        color:      '#a19f9d',
        textTransform: 'uppercase',
        letterSpacing: '0.4px',
    },
    detailValue: {
        fontSize:   '13px',
        color:      '#323130',
        lineHeight: '20px',
    },
    td: {
        padding:       '8px 12px',
        verticalAlign: 'middle',
        overflow:      'hidden',
        textOverflow:  'ellipsis',
        whiteSpace:    'nowrap',
        lineHeight:    '20px',
        // No fixed maxWidth — cells shrink/grow with table-layout:fixed
    },
    tdPresence: {
        width:     '80px',
        textAlign: 'center',
        padding:   '8px 0',
    },
    agentName: {
        color:  '#106ebe',
        cursor: 'pointer',
        ':hover': {
            textDecoration: 'underline',
        },
    },

    // ── edit action column ────────────────────────────────────────────────────
    tdAction: {
        width:         '84px',
        minWidth:      '84px',
        padding:       '0 6px',
        textAlign:     'center',
        verticalAlign: 'middle',
        whiteSpace:    'nowrap',
    },
    editBtn: {
        background:   'none',
        border:       'none',
        cursor:       'pointer',
        padding:      '4px',
        color:        '#a19f9d',
        display:      'inline-flex',
        alignItems:   'center',
        justifyContent: 'center',
        borderRadius: '4px',
        opacity:      '0',
        transition:   'opacity 0.15s, color 0.15s, background-color 0.15s',
        ':hover': {
            color:           '#0f6cbd',
            backgroundColor: '#e1effa',
        },
    },
    editBtnVisible: {
        opacity: '1',
    },
    editBtnDisabled: {
        opacity:         '1',
        cursor:          'not-allowed',
        color:           '#c8c6c4',
        ':hover': {
            color:           '#c8c6c4',
            backgroundColor: 'transparent',
        },
    },

    // ── presence picker popover ───────────────────────────────────────────────
    pickerOverlay: {
        position:        'fixed',
        inset:           '0',
        zIndex:          '9999',
        background:      'rgba(0,0,0,0.50)',
        display:         'flex',
        alignItems:      'center',
        justifyContent:  'center',
    },
    picker: {
        position:      'relative',
        zIndex:        '10000',
        background:    '#ffffff',
        border:        '1px solid #c8c6c4',
        borderRadius:  '8px',
        boxShadow:     '0 8px 32px rgba(0,0,0,0.22)',
        width:         '320px',
        maxWidth:      '90vw',
        maxHeight:     '80vh',
        display:       'flex',
        flexDirection: 'column',
        overflow:      'hidden',
    },
    pickerHeader: {
        padding:         '14px 16px 12px',
        fontSize:        '14px',
        fontWeight:      '600',
        color:           '#323130',
        borderBottom:    '1px solid #edebe9',
        display:         'flex',
        alignItems:      'center',
        justifyContent:  'space-between',
        flexShrink:      '0',
    },
    pickerHeaderTitle: {
        fontSize:   '14px',
        fontWeight: '600',
        color:      '#323130',
    },
    pickerCloseBtn: {
        background:   'none',
        border:       'none',
        cursor:       'pointer',
        padding:      '2px 4px',
        color:        '#605e5c',
        fontSize:     '16px',
        lineHeight:   '1',
        borderRadius: '4px',
        display:      'inline-flex',
        alignItems:   'center',
        ':hover': {
            color:           '#323130',
            backgroundColor: '#edebe9',
        },
    },
    pickerSubtitle: {
        padding:    '6px 16px 8px',
        fontSize:   '11px',
        fontWeight: '600',
        color:      '#a19f9d',
        textTransform: 'uppercase',
        letterSpacing: '0.4px',
        borderBottom:  '1px solid #edebe9',
        flexShrink:    '0',
    },
    pickerList: {
        overflowY:  'auto',
        flexGrow:   '1',
        padding:    '4px 0',
    },
    pickerItem: {
        display:    'flex',
        alignItems: 'center',
        gap:        '10px',
        padding:    '9px 16px',
        cursor:     'pointer',
        fontSize:   '13px',
        color:      '#323130',
        ':hover': {
            backgroundColor: '#f3f2f1',
        },
    },
    pickerItemActive: {
        backgroundColor: '#e1effa',
        color:           '#106ebe',
    },
    pickerSaving: {
        padding:   '10px 12px',
        fontSize:  '12px',
        color:     '#605e5c',
        display:   'flex',
        alignItems: 'center',
        gap:       '8px',
    },
    pickerError: {
        padding:  '8px 12px',
        fontSize: '12px',
        color:    '#a4262c',
    },
    pickerNote: {
        padding:         '8px 14px 10px',
        fontSize:        '11px',
        color:           '#605e5c',
        backgroundColor: '#faf9f8',
        borderTop:       '1px solid #edebe9',
        display:         'flex',
        alignItems:      'flex-start',
        gap:             '6px',
        lineHeight:      '16px',
    },

    // ── history modal ─────────────────────────────────────────────────────────
    historyModalOverlay: {
        position:       'fixed',
        inset:          '0',
        zIndex:         '10001',
        background:     'rgba(0,0,0,0.50)',
        display:        'flex',
        alignItems:     'center',
        justifyContent: 'center',
        padding:        '24px',
    },
    historyModal: {
        position:      'relative',
        background:    '#ffffff',
        borderRadius:  '10px',
        boxShadow:     '0 16px 48px rgba(0,0,0,0.24)',
        width:         '720px',
        maxWidth:      '95vw',
        height:        '85vh',
        display:       'flex',
        flexDirection: 'column',
        overflow:      'hidden',
    },
    historyModalHeader: {
        padding:         '16px 20px 14px',
        borderBottom:    '1px solid #edebe9',
        display:         'flex',
        alignItems:      'center',
        gap:             '10px',
        flexShrink:      '0',
        backgroundColor: '#f3f2f1',
    },
    historyModalTitle: {
        fontWeight:  '600',
        fontSize:    '15px',
        color:       '#323130',
        flex:        '1',
    },
    historyModalSubtitle: {
        fontSize: '12px',
        color:    '#a19f9d',
        marginTop: '1px',
    },
    historyModalClose: {
        background:   'none',
        border:       'none',
        cursor:       'pointer',
        padding:      '4px 6px',
        fontSize:     '18px',
        color:        '#605e5c',
        lineHeight:   '1',
        borderRadius: '4px',
        ':hover': { backgroundColor: '#edebe9', color: '#323130' },
    },
    historyModalBody: {
        overflowY:  'auto',
        flex:       '1',
        padding:    '0 0 16px',
    },
    historyModalLoading: {
        display:        'flex',
        alignItems:     'center',
        justifyContent: 'center',
        gap:            '10px',
        padding:        '48px 24px',
        color:          '#605e5c',
        fontSize:       '13px',
    },
    historyModalError: {
        padding:  '24px',
        color:    '#a4262c',
        fontSize: '13px',
    },
    historyModalEmpty: {
        padding:   '48px 24px',
        textAlign: 'center',
        color:     '#a19f9d',
        fontSize:  '13px',
    },
    // Day section
    historyDaySection: {
        marginBottom: '0',
    },
    historyDayHeader: {
        display:         'flex',
        alignItems:      'center',
        gap:             '10px',
        padding:         '10px 20px 8px',
        backgroundColor: '#f3f2f1',
        borderTop:       '1px solid #edebe9',
        borderBottom:    '1px solid #edebe9',
        position:        'sticky',
        top:             '0',
        zIndex:          '1',
        cursor:          'pointer',
        userSelect:      'none',
        ':hover': {
            backgroundColor: '#ebe9e8',
        },
    },
    historyDayLabel: {
        fontWeight:  '600',
        fontSize:    '12px',
        color:       '#323130',
        flex:        '1',
        textTransform: 'uppercase',
        letterSpacing: '0.5px',
    },
    historyDayChevron: {
        fontSize:   '10px',
        color:      '#605e5c',
        transition: 'transform 0.15s',
        flexShrink: '0',
    },
    historyDayTotal: {
        fontSize:    '11px',
        color:       '#605e5c',
        whiteSpace:  'nowrap',
    },
    // Day summary bar
    historyDaySummaryBar: {
        display:     'flex',
        height:      '6px',
        borderRadius: '3px',
        overflow:    'hidden',
        width:       '160px',
        flexShrink:  '0',
    },
    // Day summary pills row
    historyDaySummaryPills: {
        display:     'flex',
        flexWrap:    'wrap',
        gap:         '4px',
        padding:     '6px 20px 8px',
        borderBottom: '1px solid #f3f2f1',
    },
    historyDaySummaryPill: {
        display:      'flex',
        alignItems:   'center',
        gap:          '4px',
        padding:      '2px 8px',
        borderRadius: '10px',
        fontSize:     '11px',
        fontWeight:   '500',
        backgroundColor: '#f3f2f1',
        color:        '#323130',
        border:       '1px solid #edebe9',
        cursor:       'pointer',
        transition:   'background-color 0.12s, border-color 0.12s',
        ':hover': {
            backgroundColor: '#e1effa',
            borderColor:     '#0f6cbd',
        },
    },
    historyDaySummaryPillActive: {
        backgroundColor: '#cfe4f5',
        borderColor:     '#0f6cbd',
        boxShadow:       '0 0 0 1px #0f6cbd',
    },
    // Timeline entries
    historyTimeline: {
        padding:  '4px 20px 4px 20px',
        position: 'relative',
    },
    historyTimelineEntry: {
        display:       'grid',
        gridTemplateColumns: '54px 16px 1fr',
        gap:           '0 10px',
        alignItems:    'start',
        minHeight:     '40px',
        position:      'relative',
    },
    historyTimelineTime: {
        textAlign:  'right',
        fontSize:   '11px',
        color:      '#a19f9d',
        paddingTop: '10px',
        whiteSpace: 'nowrap',
    },
    historyTimelineDotCol: {
        display:        'flex',
        flexDirection:  'column',
        alignItems:     'center',
    },
    historyTimelineDot: {
        width:        '14px',
        height:       '14px',
        borderRadius: '50%',
        flexShrink:   '0',
        marginTop:    '8px',
        border:       '2px solid #ffffff',
        boxShadow:    '0 0 0 1.5px currentColor',
        zIndex:       '1',
    },
    historyTimelineLine: {
        width:      '2px',
        flex:       '1',
        minHeight:  '20px',
        backgroundColor: '#edebe9',
        marginTop:  '2px',
    },
    historyTimelineCard: {
        backgroundColor: '#faf9f8',
        border:          '1px solid #edebe9',
        borderRadius:    '6px',
        padding:         '8px 12px',
        marginBottom:    '6px',
        marginTop:       '4px',
    },
    historyTimelineCardActive: {
        backgroundColor: '#e1effa',
        borderColor:     '#0f6cbd',
    },
    historyTimelineCardTitle: {
        fontWeight:  '600',
        fontSize:    '13px',
        color:       '#323130',
        display:     'flex',
        alignItems:  'center',
        gap:         '6px',
    },
    historyTimelineCardMeta: {
        fontSize:    '11px',
        color:       '#605e5c',
        marginTop:   '3px',
        display:     'flex',
        gap:         '12px',
    },
    groupHeaderTr: {
        borderBottom: '1px solid #edebe9',
        cursor:       'pointer',
        ':hover': {
            backgroundColor: '#f3f2f1',
        },
    },
    groupHeaderTd: {
        padding:         '6px 12px',
        fontWeight:      '600',
        fontSize:        '12px',
        color:           '#605e5c',
        backgroundColor: '#faf9f8',
    },
    groupHeaderContent: {
        display:    'flex',
        alignItems: 'center',
        gap:        '6px',
    },
    groupCount: {
        fontWeight: '400',
        color:      '#a19f9d',
        fontSize:   '12px',
    },

    // ── footer ────────────────────────────────────────────────────────────────
    footer: {
        padding:      '8px 16px',
        borderTop:    '1px solid #edebe9',
        fontSize:     '12px',
        color:        '#605e5c',
        backgroundColor: '#ffffff',
        flexShrink:   '0',
    },

    // ── states ────────────────────────────────────────────────────────────────
    loadingState: {
        display:        'flex',
        flexDirection:  'column',
        alignItems:     'center',
        justifyContent: 'center',
        padding:        '48px 16px',
        gap:            '12px',
    },
    errorState: {
        display:        'flex',
        flexDirection:  'column',
        alignItems:     'center',
        justifyContent: 'center',
        padding:        '48px 16px',
        gap:            '12px',
        color:          '#a4262c',
        textAlign:      'center',
    },
    emptyStateTd: {
        padding:   '48px 16px',
        textAlign: 'center',
        color:     '#a19f9d',
        fontSize:  '13px',
    },

    // ── history timeline ──────────────────────────────────────────────────────
    historySection: {
        padding:     '10px 16px 12px 48px',
        borderTop:   '1px solid #edebe9',
    },
    historySectionTitle: {
        fontSize:    '11px',
        fontWeight:  '600',
        color:       '#a19f9d',
        textTransform: 'uppercase',
        letterSpacing: '0.4px',
        marginBottom: '8px',
        display:     'flex',
        alignItems:  'center',
        gap:         '6px',
    },
    historyRefreshBtn: {
        background:   'none',
        border:       'none',
        cursor:       'pointer',
        padding:      '2px',
        color:        '#8a8886',
        display:      'inline-flex',
        alignItems:   'center',
        borderRadius: '3px',
        lineHeight:   '1',
        opacity:      '0.8',
        ':hover': {
            opacity:         '1',
            backgroundColor: 'transparent',
        },
    },
    historyTimelineWrap: {
        overflowX:  'auto',
        paddingBottom: '4px',
    },
    historyBarTrack: {
        display:        'flex',
        flexDirection:  'row',
        height:         '24px',
        borderRadius:   '4px',
        overflow:       'hidden',
        minWidth:       '200px',
    },
    historyTableWrap: {
        marginTop:  '8px',
        overflowX:  'auto',
    },
    historyTable: {
        width:          '100%',
        borderCollapse: 'collapse',
        fontSize:       '12px',
        color:          '#323130',
    },
    historyTh: {
        textAlign:    'left',
        fontWeight:   '600',
        fontSize:     '11px',
        color:        '#605e5c',
        padding:      '3px 8px',
        borderBottom: '1px solid #edebe9',
        whiteSpace:   'nowrap',
    },
    historyTd: {
        padding:      '4px 8px',
        borderBottom: '1px solid #f3f2f1',
        whiteSpace:   'nowrap',
        verticalAlign: 'middle',
    },
    historyLoadingRow: {
        display:    'flex',
        alignItems: 'center',
        gap:        '8px',
        fontSize:   '12px',
        color:      '#605e5c',
        padding:    '8px 0',
    },
    historyErrorRow: {
        fontSize: '12px',
        color:    '#a4262c',
        padding:  '6px 0',
    },
    historyEmpty: {
        fontSize: '12px',
        color:    '#a19f9d',
        padding:  '6px 0',
    },
});

// ─────────────────────────────────────────────────────────────────────────────
// Data interfaces
// ─────────────────────────────────────────────────────────────────────────────

interface IAgentRef {
    systemuserid?:  string;
    fullname?:      string;
    applicationid?: string | null;
    isdisabled?:    boolean;
}
interface IPresenceRef {
    msdyn_presenceid?:         string;
    msdyn_name?:               string;
    msdyn_basepresencestatus?: number;
    msdyn_presencestatustext?: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pure helpers
// ─────────────────────────────────────────────────────────────────────────────

/** Strip curly braces and lowercase — normalises all GUID formats for safe comparison */
function normalizeGuid(value: string): string {
    return value.replace(/[{}]/g, '').toLowerCase().trim();
}

/** O(n) diff — uses the stable Map stored in agentMapRef to avoid rebuilding on every poll */
function hasDataChangedFast(
    prevMap: Map<string, IAgentStatusRecord>,
    next:    IAgentStatusRecord[],
): boolean {
    if (prevMap.size !== next.length) return true;
    for (const n of next) {
        const p = prevMap.get(n.id);
        if (!p
            || p.presenceName         !== n.presenceName
            || p.isLoggedIn           !== n.isLoggedIn
            || p.startTime?.getTime() !== n.startTime?.getTime()
            || p.agentName            !== n.agentName
        ) return true;
    }
    return false;
}

/** O(log n) left-bound binary search over a sorted cumulative-heights array */
function binarySearchLeft(arr: number[], val: number): number {
    let lo = 0, hi = arr.length - 1;
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if ((arr[mid] ?? 0) < val) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}

/**
 * Fetches all pages of a Dataverse entity using the nextLink returned in each response.
 * First page uses PCF WebAPI; subsequent pages use window.fetch (same-origin).
 */
async function fetchAllPages(
    webAPI:     ComponentFramework.WebApi,
    entityType: string,
    options:    string,
    pageSize  = 5000,
): Promise<ComponentFramework.WebApi.Entity[]> {
    const all: ComponentFramework.WebApi.Entity[] = [];
    let res = await webAPI.retrieveMultipleRecords(entityType, options, pageSize);
    all.push(...res.entities);
    while (res.nextLink) {
        const pageRes = await window.fetch(res.nextLink, {
            credentials: 'same-origin',
            headers: {
                'OData-MaxVersion': '4.0',
                'OData-Version':    '4.0',
                'Accept':           'application/json',
                'Prefer':           `odata.maxpagesize=${pageSize}`,
            },
        });
        if (!pageRes.ok) break;
        const json = await pageRes.json() as {
            value?:               ComponentFramework.WebApi.Entity[];
            nextLink?:            string;
        };
        const entities = json.value ?? [];
        all.push(...entities);
        // Use Object.entries to safely read '@odata.nextLink' (dotted key can't use dot notation)
        const rawNext = (Object.entries(json) as [string, unknown][])
            .find(([k]) => k === '@odata.nextLink' || k === 'nextLink')?.[1];
        res = { entities, nextLink: typeof rawNext === 'string' ? rawNext : '' };
    }
    return all;
}

/**
 * Runs an array of async tasks with at most `concurrency` running simultaneously.
 * Preserves result order. Safe for single-threaded JS event loop.
 */
async function pLimit<T>(tasks: (() => Promise<T>)[], concurrency: number): Promise<T[]> {
    const results: (T | undefined)[] = Array.from<T | undefined>({ length: tasks.length });
    let next = 0;
    async function worker(): Promise<void> {
        while (next < tasks.length) {
            const i = next++;
            const task = tasks[i];
            if (task) results[i] = await task();
        }
    }
    await Promise.all(Array.from({ length: Math.min(concurrency, tasks.length) }, worker));
    return results as T[];
}

function mapEntities(entities: ComponentFramework.WebApi.Entity[]): IAgentStatusRecord[] {
    return entities
        .filter(e => {
            const ag = e.msdyn_agentid as IAgentRef | null;
            // Exclude bot/application users (applicationid is set) and disabled users
            if (!ag) return false;
            if (ag.applicationid != null && ag.applicationid !== '') return false;
            if (ag.isdisabled === true) return false;
            return true;
        })
        .map(e => {
            const ag = e.msdyn_agentid           as IAgentRef    | null;
            const pr = e.msdyn_currentpresenceid as IPresenceRef | null;
            const startTimeRaw: string | null =
                (e.msdyn_presencemodifiedonwithmilliseconds as string | undefined) ??
                (e.msdyn_presencemodifiedon                as string | undefined) ??
                null;
            return {
                id:                 String(e.msdyn_agentstatusid        ?? ''),
                agentId:            normalizeGuid(String(ag?.systemuserid ?? '')),
                agentName:                 ag?.fullname                 ?? 'Unknown Agent',
                presenceId:         normalizeGuid(String(pr?.msdyn_presenceid ?? '')),
                presenceName:              pr?.msdyn_name               ?? '',
                basePresenceStatus: Number(pr?.msdyn_basepresencestatus ?? 0),
                presenceStatus:     resolvePresenceStatus(
                    pr?.msdyn_name ?? '',
                    Number(pr?.msdyn_basepresencestatus ?? 0),
                ),
                isLoggedIn:        Boolean(e.msdyn_isagentloggedin      ?? false),
                startTime: startTimeRaw ? new Date(startTimeRaw) : null,
            };
        });
}

function formatDuration(startTime: Date | null): string {
    if (!startTime) return '—';
    const diffMs = Date.now() - startTime.getTime();
    if (diffMs < 0) return '—';
    const totalMinutes = Math.floor(diffMs / 60_000);
    const hours   = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    if (hours   > 0) return `${hours}h ${minutes}m`;
    if (minutes > 0) return `${minutes}m`;
    return '< 1m';
}

/** Format a duration given in milliseconds — used for history entries */
function formatDuration2(ms: number): string {
    if (ms < 0) return '00:00:00';
    const totalSecs = Math.floor(ms / 1000);
    const h = Math.floor(totalSecs / 3600);
    const m = Math.floor((totalSecs % 3600) / 60);
    const s = totalSecs % 60;
    const hh = String(h).padStart(2, '0');
    const mm = String(m).padStart(2, '0');
    const ss = String(s).padStart(2, '0');
    return `${hh}:${mm}:${ss}`;
}

function formatLastUpdated(d: Date | null): string {
    if (!d) return '';
    const secs = Math.floor((Date.now() - d.getTime()) / 1000);
    if (secs < 15)  return 'Updated just now';
    if (secs < 60)  return `Updated ${secs}s ago`;
    return `Updated ${Math.floor(secs / 60)}m ago`;
}

function sortAgents(agents: IAgentStatusRecord[], sort: ISortState): IAgentStatusRecord[] {
    return [...agents].sort((a, b) => {
        let cmp = 0;
        switch (sort.column) {
            case 'agentName': cmp = a.agentName.localeCompare(b.agentName);      break;
            case 'presence':  cmp = a.presenceName.localeCompare(b.presenceName); break;
        }
        return sort.direction === 'asc' ? cmp : -cmp;
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// Presence status colours (Teams-style) — used in timeline bars
// ─────────────────────────────────────────────────────────────────────────────

const PRESENCE_COLORS: Record<PresenceStatus, string> = {
    available:     '#92c353',
    busy:          '#c4314b',
    donotdisturb:  '#c4314b',
    berightback:   '#ffaa44',
    away:          '#ffaa44',
    offline:       '#8a8886',
    unknown:       '#c8c6c4',
};

// ─────────────────────────────────────────────────────────────────────────────
// History Timeline sub-component
// ─────────────────────────────────────────────────────────────────────────────

interface IHistoryTimelineProps {
    history: IAgentHistory;
}

const HistoryTimeline: React.FC<IHistoryTimelineProps> = ({ history }) => {
    const styles = useStyles();

    if (history.loading) {
        return (
            <div className={styles.historyLoadingRow}>
                <Spinner size="tiny" /> Loading history…
            </div>
        );
    }

    if (history.error) {
        return <div className={styles.historyErrorRow}>⚠ {history.error}</div>;
    }

    if (history.entries.length === 0) {
        return <div className={styles.historyEmpty}>No history records found for today.</div>;
    }

    // Total time span across all entries for proportional bar widths
    const totalMs = history.entries.reduce((sum, e) => sum + e.durationMs, 0);

    return (
        <>
            {/* Proportional colour bar */}
            <div className={styles.historyTimelineWrap}>
                <div className={styles.historyBarTrack} title="Presence timeline (proportional)">
                    {history.entries.map((e, i) => {
                        const pct = totalMs > 0 ? (e.durationMs / totalMs) * 100 : 0;
                        return (
                            <div
                                key={i}
                                title={`${e.presenceName} — ${formatDuration2(e.durationMs)}`}
                                style={{
                                    width:           `${pct}%`,
                                    minWidth:        pct > 0 ? '2px' : '0',
                                    backgroundColor: PRESENCE_COLORS[e.presenceStatus] ?? '#c8c6c4',
                                    transition:      'width 0.3s',
                                }}
                            />
                        );
                    })}
                </div>
            </div>

            {/* Detail table */}
            <div className={styles.historyTableWrap}>
                <table className={styles.historyTable}>
                    <thead>
                        <tr>
                            <th className={styles.historyTh}>Presence</th>
                            <th className={styles.historyTh}>Start</th>
                            <th className={styles.historyTh}>End</th>
                            <th className={styles.historyTh}>Duration</th>
                        </tr>
                    </thead>
                    <tbody>
                        {history.entries.map((e, i) => (
                            <tr key={i}>
                                <td className={styles.historyTd}>
                                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                                        <span style={{
                                            display:         'inline-block',
                                            width:           '8px',
                                            height:          '8px',
                                            borderRadius:    '50%',
                                            backgroundColor: PRESENCE_COLORS[e.presenceStatus] ?? '#c8c6c4',
                                            flexShrink:      0,
                                        }} />
                                        {e.presenceName}
                                    </div>
                                </td>
                                <td className={styles.historyTd}>
                                    {e.startTime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                                </td>
                                <td className={styles.historyTd}>
                                    {e.endTime
                                        ? e.endTime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
                                        : <Badge color="success" appearance="tint" size="small">Now</Badge>
                                    }
                                </td>
                                <td className={styles.historyTd}>{formatDuration2(e.durationMs)}</td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </>
    );
};

// ─────────────────────────────────────────────────────────────────────────────
// Status Summary Bar
// ─────────────────────────────────────────────────────────────────────────────

interface IStatusSummaryBarProps {
    agents:         IAgentStatusRecord[];
    activeFilter:   PresenceStatus | null;
    onFilter:       (s: PresenceStatus | null) => void;
}

const StatusSummaryBar: React.FC<IStatusSummaryBarProps> = ({ agents, activeFilter, onFilter }) => {
    const styles = useStyles();
    const counts = useMemo(() => {
        const map = new Map<PresenceStatus, number>();
        for (const a of agents) {
            map.set(a.presenceStatus, (map.get(a.presenceStatus) ?? 0) + 1);
        }
        return map;
    }, [agents]);

    return (
        <div className={styles.summaryBar}>
            <span
                className={cx(styles.summaryTotal, !activeFilter ? styles.summaryItemActive : '')}
                onClick={() => onFilter(null)}
                title="Show all agents"
            >
                {agents.length} Agents
            </span>
            {STATUS_ORDER.filter(s => counts.has(s)).map(s => (
                <div
                    key={s}
                    className={cx(styles.summaryItem, activeFilter === s ? styles.summaryItemActive : '')}
                    onClick={() => onFilter(activeFilter === s ? null : s)}
                    title={activeFilter === s ? `Clear filter: ${PRESENCE_LABELS[s]}` : `Filter by: ${PRESENCE_LABELS[s]}`}
                >
                    <PresenceIcon presenceName={PRESENCE_LABELS[s]} size={14} />
                    <span className={styles.summaryCount}>{counts.get(s)}</span>
                    <span>{PRESENCE_LABELS[s]}</span>
                </div>
            ))}
        </div>
    );
};

// ─────────────────────────────────────────────────────────────────────────────
// Sortable column header
// ─────────────────────────────────────────────────────────────────────────────

interface IColHeaderProps {
    label:      string;
    colId:      SortColumn;
    sortState:  ISortState;
    onSort:     (col: SortColumn) => void;
    extraClass?: string;
}

const ColHeader: React.FC<IColHeaderProps> = ({ label, colId, sortState, onSort, extraClass }) => {
    const styles   = useStyles();
    const isActive = sortState.column === colId;
    return (
        <th
            className={cx(styles.th, isActive ? styles.thSortActive : '', extraClass ?? '')}
            onClick={() => onSort(colId)}
            aria-sort={isActive ? (sortState.direction === 'asc' ? 'ascending' : 'descending') : 'none'}
        >
            <div className={styles.thContent}>
                <span>{label}</span>
                <span className={cx(isActive ? styles.thSortIconActive : styles.thSortIcon)}>
                    {isActive ? (sortState.direction === 'asc' ? '↑' : '↓') : '↕'}
                </span>
            </div>
        </th>
    );
};

// ─────────────────────────────────────────────────────────────────────────────
// Agent History Modal component
// ─────────────────────────────────────────────────────────────────────────────

interface IAgentHistoryModalProps {
    agent:     IAgentStatusRecord;
    data:      { days: IHistoryDay[]; loading: boolean; error: string | null };
    onClose:   () => void;
    onRefresh: () => void;
}

const AgentHistoryModal: React.FC<IAgentHistoryModalProps> = ({ agent, data, onClose, onRefresh }) => {
    const styles = useStyles();

    // Per-day collapse state (all expanded by default)
    const [collapsedDays,    setCollapsedDays]    = useState<Set<string>>(new Set());
    // Per-day active pill filter: dateKey → PresenceStatus | null (null = show all)
    const [dayPillFilter,    setDayPillFilter]    = useState<Map<string, PresenceStatus | null>>(new Map());

    const stopProp = (e: React.MouseEvent) => e.stopPropagation();

    const toggleDay = (dateKey: string) => {
        setCollapsedDays(prev => {
            const next = new Set(prev);
            if (next.has(dateKey)) { next.delete(dateKey); } else { next.add(dateKey); }
            return next;
        });
    };

    const togglePillFilter = (dateKey: string, status: PresenceStatus) => {
        setDayPillFilter(prev => {
            const next = new Map(prev);
            // Toggle: clicking active filter clears it (show all), clicking new one sets it
            next.set(dateKey, prev.get(dateKey) === status ? null : status);
            return next;
        });
    };

    const PRESENCE_ORDER: PresenceStatus[] = ['available', 'busy', 'donotdisturb', 'away', 'berightback', 'offline', 'unknown'];

    const renderSummaryBar = (summary: Map<PresenceStatus, { name: string; ms: number }>, totalMs: number) => {
        const segments: React.ReactElement[] = [];
        for (const status of PRESENCE_ORDER) {
            const entry = summary.get(status);
            if (!entry || entry.ms <= 0) continue;
            const pct = totalMs > 0 ? (entry.ms / totalMs) * 100 : 0;
            segments.push(
                <div key={status} style={{ width: `${pct}%`, backgroundColor: PRESENCE_COLORS[status], minWidth: '2px' }} title={`${entry.name}: ${formatDuration2(entry.ms)}`} />
            );
        }
        return <div className={styles.historyDaySummaryBar}>{segments}</div>;
    };

    const renderSummaryPills = (dateKey: string, summary: Map<PresenceStatus, { name: string; ms: number }>) => {
        const activeFilter = dayPillFilter.get(dateKey) ?? null;
        return (
            <div className={styles.historyDaySummaryPills}>
                {PRESENCE_ORDER.map(status => {
                    const entry = summary.get(status);
                    if (!entry || entry.ms <= 0) return null;
                    const isActive = activeFilter === status;
                    return (
                        <div
                            key={status}
                            className={cx(styles.historyDaySummaryPill, isActive ? styles.historyDaySummaryPillActive : '')}
                            onClick={() => togglePillFilter(dateKey, status)}
                            title={isActive ? 'Click to show all' : `Filter to ${entry.name}`}
                        >
                            <span style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: PRESENCE_COLORS[status], display: 'inline-block', flexShrink: 0 }} />
                            <span style={{ color: PRESENCE_COLORS[status], fontWeight: 600 }}>{entry.name}</span>
                            <span style={{ color: '#605e5c', fontWeight: 400 }}>{formatDuration2(entry.ms)}</span>
                        </div>
                    );
                })}
                {(dayPillFilter.get(dateKey) ?? null) !== null && (
                    <div
                        className={styles.historyDaySummaryPill}
                        onClick={() => setDayPillFilter(prev => { const next = new Map(prev); next.set(dateKey, null); return next; })}
                        style={{ color: '#605e5c', fontSize: '10px', cursor: 'pointer' }}
                        title="Clear filter"
                    >
                        ✕ Clear filter
                    </div>
                )}
            </div>
        );
    };

    const renderEntries = (dateKey: string, entries: IStatusHistoryEntry[], dayIdx: number) => {
        const activeFilter = dayPillFilter.get(dateKey) ?? null;
        const visible = activeFilter ? entries.filter(e => e.presenceStatus === activeFilter) : entries;
        return visible.map((entry, idx) => {
            const isLast   = idx === visible.length - 1;
            const color    = PRESENCE_COLORS[entry.presenceStatus ?? 'unknown'];
            const isActive = !entry.endTime;
            return (
                <div key={`${dayIdx}-${idx}`} className={styles.historyTimelineEntry}>
                    <div className={styles.historyTimelineTime}>
                        {new Date(entry.startTime).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                    </div>
                    <div className={styles.historyTimelineDotCol}>
                        <div
                            className={styles.historyTimelineDot}
                            style={{
                                backgroundColor: color,
                                color: color,
                                boxShadow: isActive ? `0 0 0 3px ${color}40, 0 0 8px ${color}80` : `0 0 0 1.5px ${color}`,
                            }}
                        />
                        {!isLast && <div className={styles.historyTimelineLine} />}
                    </div>
                    <div className={`${styles.historyTimelineCard}${isActive ? ` ${styles.historyTimelineCardActive}` : ''}`}>
                        <div className={styles.historyTimelineCardTitle}>
                            <span style={{ width: '10px', height: '10px', borderRadius: '50%', backgroundColor: color, display: 'inline-block', flexShrink: 0 }} />
                            {entry.presenceName}
                            {isActive && (
                                <span style={{ marginLeft: 'auto', fontSize: '10px', fontWeight: 600, color: '#0f6cbd', backgroundColor: '#e1effa', padding: '1px 7px', borderRadius: '8px', border: '1px solid #0f6cbd' }}>
                                    Active Now
                                </span>
                            )}
                        </div>
                        <div className={styles.historyTimelineCardMeta}>
                            <span>
                                {new Date(entry.startTime).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                                {' → '}
                                {entry.endTime ? new Date(entry.endTime).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : 'Now'}
                            </span>
                            <span style={{ fontWeight: 500, color: '#323130' }}>⏱ {entry.endTime ? formatDuration2(new Date(entry.endTime).getTime() - new Date(entry.startTime).getTime()) : formatDuration2(Date.now() - new Date(entry.startTime).getTime())}</span>
                        </div>
                    </div>
                </div>
            );
        });
    };

    return (
        <div className={styles.historyModalOverlay} onClick={onClose}>
            <div className={styles.historyModal} onClick={stopProp}>
                {/* Header */}
                <div className={styles.historyModalHeader}>
                    <div style={{ flex: 1 }}>
                        <div className={styles.historyModalTitle}>
                            <PresenceIcon presenceName={agent.presenceName ?? ''} basePresenceStatus={agent.basePresenceStatus} size={18} />
                            {' '}{agent.agentName}
                        </div>
                        <div className={styles.historyModalSubtitle}>Presence History — Last 7 Days</div>
                    </div>
                    <button
                        title={data.loading ? 'Loading…' : 'Refresh'}
                        style={{
                            background: 'none', border: 'none',
                            cursor: data.loading ? 'default' : 'pointer',
                            padding: '4px',
                            display: 'inline-flex', alignItems: 'center',
                            opacity: data.loading ? 0.4 : 0.8,
                        }}
                        onClick={onRefresh}
                        disabled={data.loading}
                    >
                        {data.loading
                            ? <Spinner size="tiny" />
                            : <RefreshIcon size={16} />
                        }
                    </button>
                    <button className={styles.historyModalClose} onClick={onClose} title="Close">✕</button>
                </div>

                {/* Body */}
                <div className={styles.historyModalBody}>
                    {data.loading && !data.days.length && (
                        <div className={styles.historyModalLoading}><Spinner size="small" /> Loading presence history…</div>
                    )}
                    {data.error && <div className={styles.historyModalError}>⚠ {data.error}</div>}
                    {!data.loading && !data.error && !data.days.length && (
                        <div className={styles.historyModalEmpty}>No presence history found for the last 7 days.</div>
                    )}
                    {data.days.map((day, dayIdx) => {
                        const isCollapsed = collapsedDays.has(day.dateKey);
                        return (
                            <div key={day.dateKey} className={styles.historyDaySection}>
                                {/* Clickable day header — expands/collapses */}
                                <div
                                    className={styles.historyDayHeader}
                                    onClick={() => toggleDay(day.dateKey)}
                                    role="button"
                                    aria-expanded={!isCollapsed}
                                >
                                    <span className={styles.historyDayChevron} style={{ transform: isCollapsed ? 'rotate(-90deg)' : 'rotate(0deg)', display: 'inline-block' }}>▼</span>
                                    <div className={styles.historyDayLabel}>{day.dateLabel}</div>
                                    {renderSummaryBar(day.summary, day.totalMs)}
                                    <div className={styles.historyDayTotal}>{formatDuration2(day.totalMs)} active · {day.entries.length} events</div>
                                </div>
                                {!isCollapsed && (
                                    <>
                                        {/* Clickable presence legend pills */}
                                        {renderSummaryPills(day.dateKey, day.summary)}
                                        <div className={styles.historyTimeline}>
                                            {renderEntries(day.dateKey, day.entries, dayIdx)}
                                        </div>
                                    </>
                                )}
                            </div>
                        );
                    })}
                </div>
            </div>
        </div>
    );
};

// ─────────────────────────────────────────────────────────────────────────────
// Main component
// ─────────────────────────────────────────────────────────────────────────────

const AgentPresenceGrid: React.FC<IAgentPresenceGridProps> = ({ webAPI, userId, width, height }) => {
    const styles = useStyles();

    const rootStyle: React.CSSProperties = {
        width:  width  ? `${width}px`  : '100%',
        height: height ? `${height}px` : '100%',
    };

    // ── State ──────────────────────────────────────────────────────────────
    const [agents,            setAgents]            = useState<IAgentStatusRecord[]>([]);
    const [isInitialLoad,     setIsInitialLoad]     = useState(true);
    const [isRefreshing,      setIsRefreshing]      = useState(false);
    const [error,             setError]             = useState<string | null>(null);
    const [searchText,        setSearchText]        = useState('');
    const [debouncedSearch,   setDebouncedSearch]   = useState('');
    const [lastUpdated,       setLastUpdated]       = useState<Date | null>(null);
    const [sortState,         setSortState]         = useState<ISortState>({ column: 'agentName', direction: 'asc' });
    const [groupBy,           setGroupBy]           = useState<GroupBy>(null);
    const [collapsedGroups,   setCollapsedGroups]   = useState<Set<string>>(new Set());
    const [tick,              setTick]              = useState(0);
    const [expandedRows,      setExpandedRows]      = useState<Set<string>>(new Set());
    const [autoRefresh,       setAutoRefresh]       = useState(false);
    const [isAuthorized,      setIsAuthorized]      = useState(false);
    const [availablePresences, setAvailablePresences] = useState<IPresenceOption[]>([]);
    const [editingAgentId,    setEditingAgentId]    = useState<string | null>(null);
    const [isSaving,          setIsSaving]          = useState(false);
    const [saveError,         setSaveError]         = useState<string | null>(null);
    const [hoveredRowId,      setHoveredRowId]      = useState<string | null>(null);
    const [presenceFilter,    setPresenceFilter]    = useState<PresenceStatus | null>(null);
    const [containerHeight,   setContainerHeight]   = useState(600);
    const [scrollTop,         setScrollTop]         = useState(0);
    const [availableQueues,    setAvailableQueues]    = useState<IQueue[]>([]);
    const [selectedQueues,     setSelectedQueues]     = useState<Set<string>>(new Set());
    const [queueMembers,       setQueueMembers]       = useState<Map<string, Set<string>>>(new Map());
    const [queueFilterLoading, setQueueFilterLoading] = useState(false);
    const [queuePickerOpen,    setQueuePickerOpen]    = useState(false);
    const [queuePickerAnchor, setQueuePickerAnchor] = useState<{ top: number; left: number } | null>(null);
    const [queueSearch,       setQueueSearch]       = useState('');
    const [historyMap,        setHistoryMap]        = useState<Map<string, IAgentHistory>>(new Map());
    const [historyModalAgent, setHistoryModalAgent] = useState<IAgentStatusRecord | null>(null);
    const [historyModalData,  setHistoryModalData]  = useState<{ days: IHistoryDay[]; loading: boolean; error: string | null }>({ days: [], loading: false, error: null });

    // Tracks the agentId the modal was last opened for — prevents stale fetches overwriting data
    const historyModalAgentIdRef = useRef<string>('');

    // ── Refs ───────────────────────────────────────────────────────────────
    const isMountedRef      = useRef(true);
    const inFlightRef       = useRef(false);
    const webAPIRef         = useRef(webAPI);
    const agentMapRef       = useRef(new Map<string, IAgentStatusRecord>());
    const tableContainerRef = useRef<HTMLDivElement>(null);
    // Maps presenceid → { name, presenceStatus } — populated when presences are loaded
    const presenceNameMapRef = useRef(new Map<string, { name: string; presenceStatus: PresenceStatus }>());
    useEffect(() => { webAPIRef.current = webAPI; }, [webAPI]);
    useEffect(() => {
        isMountedRef.current = true;
        return () => { isMountedRef.current = false; };
    }, []);

    // ── 200ms debounce for search — avoids filtering 30K records on every keystroke ──
    useEffect(() => {
        const id = setTimeout(() => setDebouncedSearch(searchText.trim().toLowerCase()), 200);
        return () => clearTimeout(id);
    }, [searchText]);

    // ── Track scroll container dimensions for virtual scrolling ───────────
    useEffect(() => {
        const el = tableContainerRef.current;
        if (!el) return;
        const obs = new ResizeObserver(entries => {
            const h = entries[0]?.contentRect.height ?? el.clientHeight;
            setContainerHeight(h);
        });
        obs.observe(el);
        setContainerHeight(el.clientHeight);
        return () => obs.disconnect();
    }, []);

    // ── Data fetching ──────────────────────────────────────────────────────
    const fetchAgentData = useCallback(async (isBackground: boolean): Promise<void> => {
        if (inFlightRef.current) return;
        inFlightRef.current = true;
        setIsRefreshing(true);
        try {
            const entities = await fetchAllPages(webAPIRef.current, 'msdyn_agentstatus', ODATA_OPTIONS, 5000);
            if (!isMountedRef.current) return;
            const mapped = mapEntities(entities);
            if (hasDataChangedFast(agentMapRef.current, mapped)) {
                agentMapRef.current = new Map(mapped.map(r => [r.id, r]));
                setAgents(mapped);
            }
            setLastUpdated(new Date());
            setError(null);
        } catch (err) {
            if (!isMountedRef.current) return;
            if (!isBackground) setError(`Unable to load agent data: ${(err as Error).message ?? String(err)}`);
        } finally {
            if (isMountedRef.current) { setIsInitialLoad(false); setIsRefreshing(false); }
            inFlightRef.current = false;
        }
    }, []);

    useEffect(() => {
        void fetchAgentData(false);
        if (!autoRefresh) return;
        const id = setInterval(() => { void fetchAgentData(true); }, POLL_INTERVAL_MS);
        return () => clearInterval(id);
    }, [fetchAgentData, autoRefresh]);

    // 30s ticker to keep duration cells current without a new Dataverse request
    useEffect(() => {
        const id = setInterval(() => setTick(t => t + 1), 30_000);
        return () => clearInterval(id);
    }, []);

    // ── Security role check ────────────────────────────────────────────────
    useEffect(() => {
        if (!userId) return;
        const uid = userId.replace(/[{}]/g, '');
        void (async () => {
            try {
                const res = await webAPIRef.current.retrieveRecord(
                    'systemuser', uid,
                    '?$expand=systemuserroles_association($select=name)',
                );
                if (!isMountedRef.current) return;
                const roles = (res.systemuserroles_association as { name?: string }[] | undefined) ?? [];
                const authorized = roles.some(r => {
                    const n = (r.name ?? '').toLowerCase();
                    return n.includes('system administrator') || n.includes('omnichannel supervisor');
                });
                setIsAuthorized(authorized);
            } catch {
                // non-critical — leave isAuthorized false
            }
        })();
    }, [userId]);

    // ── Fetch all presences for the picker ─────────────────────────────────
    useEffect(() => {
        void (async () => {
            try {
                const res = await webAPIRef.current.retrieveMultipleRecords(
                    'msdyn_presence',
                    '?$select=msdyn_presenceid,msdyn_name,msdyn_basepresencestatus,msdyn_canuserset&$orderby=msdyn_basepresencestatus asc',
                    100,
                );
                if (!isMountedRef.current) return;

                // Populate presenceNameMapRef with ALL presences (including canUserSet=false)
                // so history entries can resolve presenceid → name + status.
                for (const e of res.entities) {
                    const pid  = normalizeGuid((e.msdyn_presenceid as string) ?? '');
                    const name = (e.msdyn_name as string) ?? '';
                    const base = (e.msdyn_basepresencestatus as number) ?? 0;
                    if (pid) presenceNameMapRef.current.set(pid, { name, presenceStatus: resolvePresenceStatus(name, base) });
                }

                // Picker only shows presences where canUserSet = true
                setAvailablePresences(
                    res.entities
                        .filter(e => e.msdyn_canuserset === true)
                        .map(e => ({
                            id:                 (e.msdyn_presenceid as string) ?? '',
                            name:               (e.msdyn_name as string) ?? '',
                            basePresenceStatus: (e.msdyn_basepresencestatus as number) ?? 0,
                            canUserSet:         true,
                        })),
                );
            } catch {
                // non-critical
            }
        })();
    }, []);

    // ── Fetch Omnichannel queue list (once on mount) ───────────────────────
    useEffect(() => {
        void (async () => {
            try {
                const entities = await fetchAllPages(
                    webAPIRef.current,
                    'queue',
                    '?$select=queueid,name&$filter=msdyn_isomnichannelqueue eq true&$orderby=name asc',
                    500,
                );
                if (!isMountedRef.current) return;
                const queues: IQueue[] = entities
                    .map(e => ({
                        id:   normalizeGuid((e.queueid as string) ?? ''),
                        name: (e.name as string) ?? '',
                    }))
                    .filter(q => q.id);
                setAvailableQueues(queues);
            } catch (err) {
                console.error('[AgentPresenceControl] Queue list fetch failed:', String(err));
            }
        })();
    }, []);

    // ── Fetch members for selected queues (re-runs on every selection change) ─
    useEffect(() => {
        if (selectedQueues.size === 0) {
            setQueueMembers(new Map());
            return;
        }

        const selectedIds = [...selectedQueues];
        let cancelled = false;

        void (async () => {
            setQueueFilterLoading(true);
            try {
                // Fetch memberships for all currently selected queues.
                // pLimit caps concurrent HTTP requests at QUEUE_FETCH_CONCURRENCY (5)
                // so selecting many queues at once doesn't flood the API.
                // Each task is scoped to one queue — avoids fetching the entire intersect table.
                const results = await pLimit(
                    selectedIds.map(qid => () =>
                        webAPIRef.current.retrieveMultipleRecords(
                            'queuemembership',
                            `?$select=queueid,systemuserid&$filter=queueid eq ${qid}`,
                            5000,
                        ).then(r => ({ qid, entities: r.entities }))
                         .catch(err => {
                             console.error(`[AgentPresenceControl] Member fetch failed for queue ${qid}:`, String(err));
                             return { qid, entities: [] as ComponentFramework.WebApi.Entity[] };
                         })
                    ),
                    QUEUE_FETCH_CONCURRENCY,
                );
                if (cancelled || !isMountedRef.current) return;

                const map = new Map<string, Set<string>>();
                for (const { qid, entities } of results) {
                    const memberSet = new Set<string>();
                    for (const m of entities) {
                        const entries = Object.entries(m) as [string, unknown][];
                        const uidRaw = (entries.find(([k]) => k.toLowerCase() === 'systemuserid')?.[1] as string | undefined) ?? '';
                        const uid = normalizeGuid(uidRaw);
                        if (uid) memberSet.add(uid);
                    }
                    map.set(qid, memberSet);
                }
                setQueueMembers(map);
            } catch (err) {
                console.error('[AgentPresenceControl] Queue member fetch failed:', String(err));
            } finally {
                if (!cancelled) setQueueFilterLoading(false);
            }
        })();

        return () => { cancelled = true; };
    }, [selectedQueues]);

    // ── Modify agent presence via CCaaS API ───────────────────────────────
    const modifyPresence = useCallback(async (agentId: string, presenceId: string): Promise<void> => {
        const cleanAgentId    = normalizeGuid(agentId);
        const cleanPresenceId = normalizeGuid(presenceId);
        if (!cleanAgentId || !cleanPresenceId) {
            setSaveError('Cannot update: agent or presence ID is missing.');
            return;
        }
        setIsSaving(true);
        setSaveError(null);
        try {
            const response = await fetch('/api/data/v9.2/CCaaS_ModifyAgentPresence', {
                method:  'POST',
                headers: {
                    'Content-Type':     'application/json',
                    'OData-MaxVersion': '4.0',
                    'OData-Version':    '4.0',
                    'Accept':           'application/json',
                },
                body: JSON.stringify({ ApiVersion: '1.0', AgentId: cleanAgentId, PresenceId: cleanPresenceId }),
            });
            if (!response.ok) {
                const text = await response.text().catch(() => response.statusText);
                throw new Error(`API error ${response.status}: ${text}`);
            }
            setEditingAgentId(null);
            // Refresh immediately so the grid shows the new status
            void fetchAgentData(true);
        } catch (err) {
            setSaveError((err as Error).message ?? 'Failed to update presence.');
        } finally {
            setIsSaving(false);
        }
    }, [fetchAgentData]);

    const openPicker = useCallback((agentId: string) => {
        setEditingAgentId(agentId);
        setSaveError(null);
    }, []);

    const closePicker = useCallback(() => {
        setEditingAgentId(null);
        setSaveError(null);
    }, []);

    // ── Fetch presence history for one agent (also called by refresh button) ─
    const fetchHistory = useCallback((agentRecord: IAgentStatusRecord) => {
        setHistoryMap(prev => {
            const next = new Map(prev);
            next.set(agentRecord.agentId, { entries: [], loading: true, error: null });
            return next;
        });

        void (async () => {
            try {
                const agentFilter = `_msdyn_agentid_value eq '${agentRecord.agentId}'`;
                const since       = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
                const opts        = `?$select=msdyn_starttime,msdyn_endtime` +
                                    `&$expand=msdyn_presenceid($select=msdyn_presenceid,msdyn_name,msdyn_basepresencestatus)` +
                                    `&$filter=${agentFilter} and msdyn_starttime ge ${since}` +
                                    `&$orderby=msdyn_starttime desc` +
                                    `&$top=50`;

                const res = await webAPIRef.current.retrieveMultipleRecords(
                    'msdyn_agentstatushistory',
                    opts,
                    50,
                );
                if (!isMountedRef.current) return;

                const entries: IStatusHistoryEntry[] = res.entities
                    .map(e => {
                        const presRef  = e.msdyn_presenceid as { msdyn_presenceid?: string; msdyn_name?: string; msdyn_basepresencestatus?: number } | null;
                        const pid      = normalizeGuid(presRef?.msdyn_presenceid ?? '');
                        const presName = presRef?.msdyn_name ?? '';
                        const presBase = presRef?.msdyn_basepresencestatus ?? 0;
                        const presInfo = presName ? null : presenceNameMapRef.current.get(pid);
                        const start    = new Date((e.msdyn_starttime as string) ?? '');
                        const endRaw   = e.msdyn_endtime as string | undefined | null;
                        const end      = endRaw ? new Date(endRaw) : null;
                        const durMs    = (end ? end.getTime() : Date.now()) - start.getTime();
                        return {
                            presenceId:     pid,
                            presenceName:   presName !== '' ? presName : (presInfo?.name ?? 'Unknown'),
                            presenceStatus: presName  ? resolvePresenceStatus(presName, presBase)
                                                      : (presInfo?.presenceStatus ?? 'unknown'),
                            startTime:      start,
                            endTime:        end,
                            durationMs:     Math.max(0, durMs),
                        } as IStatusHistoryEntry;
                    })
                    .filter(e => !isNaN(e.startTime.getTime()));

                setHistoryMap(prev => {
                    const next = new Map(prev);
                    next.set(agentRecord.agentId, { entries, loading: false, error: null });
                    return next;
                });
            } catch (err) {
                if (!isMountedRef.current) return;
                setHistoryMap(prev => {
                    const next = new Map(prev);
                    next.set(agentRecord.agentId, {
                        entries: [],
                        loading: false,
                        error:   `Failed to load history: ${(err as Error).message ?? String(err)}`,
                    });
                    return next;
                });
            }
        })();
    }, []);

    // ── Row expand toggle ──────────────────────────────────────────────────
    const toggleExpand = useCallback((agentRecord: IAgentStatusRecord) => {
        const id = agentRecord.id;
        setExpandedRows(prev => {
            const next = new Set(prev);
            if (next.has(id)) { next.delete(id); return next; }
            next.add(id);
            return next;
        });
        // Only fetch history when opening, not closing
        setExpandedRows(current => {
            if (current.has(id)) fetchHistory(agentRecord);
            return current;
        });
    }, [fetchHistory]);

    // ── History Modal fetch ────────────────────────────────────────────────
    const fetchHistoryModal = useCallback((agentRecord: IAgentStatusRecord) => {
        const targetAgentId = agentRecord.agentId;
        if (!targetAgentId) {
            setHistoryModalData({ days: [], loading: false, error: 'Agent ID is unavailable for this record.' });
            return;
        }

        // Mark this agent as the active fetch target
        historyModalAgentIdRef.current = targetAgentId;
        setHistoryModalData({ days: [], loading: true, error: null });

        void (async () => {
            try {
                const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
                const agentFilter = `_msdyn_agentid_value eq '${targetAgentId}'`;
                const opts  = `?$select=msdyn_starttime,msdyn_endtime` +
                              `&$expand=msdyn_presenceid($select=msdyn_presenceid,msdyn_name,msdyn_basepresencestatus)` +
                              `&$filter=${agentFilter} and msdyn_starttime ge ${since}` +
                              `&$orderby=msdyn_starttime desc` +
                              `&$top=500`;

                const res = await webAPIRef.current.retrieveMultipleRecords('msdyn_agentstatushistory', opts, 500);

                // Discard result if a different agent's modal was opened while this was in flight
                if (historyModalAgentIdRef.current !== targetAgentId) return;

                const entries: IStatusHistoryEntry[] = res.entities
                    .map(e => {
                        const presRef  = e.msdyn_presenceid as { msdyn_presenceid?: string; msdyn_name?: string; msdyn_basepresencestatus?: number } | null;
                        const pid      = normalizeGuid(presRef?.msdyn_presenceid ?? '');
                        const presName = presRef?.msdyn_name ?? '';
                        const presBase = presRef?.msdyn_basepresencestatus ?? 0;
                        const presInfo = presName ? null : presenceNameMapRef.current.get(pid);
                        const startRaw = e.msdyn_starttime as string | undefined;
                        const endRaw   = e.msdyn_endtime as string | undefined | null;
                        if (!startRaw) return null;
                        const start  = new Date(startRaw);
                        const end    = endRaw ? new Date(endRaw) : null;
                        const durMs  = (end ? end.getTime() : Date.now()) - start.getTime();
                        return {
                            presenceId:     pid,
                            presenceName:   presName !== '' ? presName : (presInfo?.name ?? 'Unknown'),
                            presenceStatus: presName  ? resolvePresenceStatus(presName, presBase)
                                                      : (presInfo?.presenceStatus ?? 'unknown'),
                            startTime:      start,
                            endTime:        end,
                            durationMs:     Math.max(0, durMs),
                        } as IStatusHistoryEntry;
                    })
                    .filter((e): e is IStatusHistoryEntry => e !== null && !isNaN(e.startTime.getTime()));

                // Group by local date (most-recent day first)
                const dayMap = new Map<string, IStatusHistoryEntry[]>();
                for (const entry of entries) {
                    const d   = entry.startTime.toLocaleDateString('en-CA'); // YYYY-MM-DD
                    const arr = dayMap.get(d) ?? [];
                    arr.push(entry);
                    dayMap.set(d, arr);
                }
                const days: IHistoryDay[] = Array.from(dayMap.entries())
                    .sort((a, b) => b[0].localeCompare(a[0]))
                    .map(([dateKey, dayEntries]) => {
                        dayEntries.sort((a, b) => b.startTime.getTime() - a.startTime.getTime());
                        const summary = new Map<PresenceStatus, { name: string; ms: number }>();
                        let totalMs = 0;
                        for (const e of dayEntries) {
                            const ms  = e.durationMs;
                            totalMs  += ms;
                            const ps  = e.presenceStatus ?? 'unknown';
                            const cur = summary.get(ps);
                            if (cur) { cur.ms += ms; }
                            else     { summary.set(ps, { name: e.presenceName, ms }); }
                        }
                        return {
                            dateKey,
                            dateLabel: new Date(`${dateKey}T12:00:00`).toLocaleDateString(undefined, { weekday: 'short', year: 'numeric', month: 'short', day: 'numeric' }),
                            entries:   dayEntries,
                            summary,
                            totalMs,
                        };
                    });

                setHistoryModalData({ days, loading: false, error: null });
            } catch (err) {
                if (historyModalAgentIdRef.current !== targetAgentId) return;
                setHistoryModalData({ days: [], loading: false, error: String(err) });
            }
        })();
    }, []);

    const handleSort = useCallback((col: SortColumn) => {
        setSortState(prev => ({
            column:    col,
            direction: prev.column === col && prev.direction === 'asc' ? 'desc' : 'asc',
        }));
    }, []);

    // ── Group collapse toggle ──────────────────────────────────────────────
    const toggleGroup = useCallback((key: string) => {
        setCollapsedGroups(prev => {
            const next = new Set(prev);
            if (next.has(key)) next.delete(key); else next.add(key);
            return next;
        });
    }, []);

    // ── Derived data ───────────────────────────────────────────────────────
    const filteredAgents = useMemo(() => {
        let result = agents;

        // Text search — uses debouncedSearch (200ms debounce) to avoid filtering 30K records on every keystroke
        if (debouncedSearch) result = result.filter(a => a.agentName.toLowerCase().includes(debouncedSearch));

        // Presence filter (from summary bar clicks) — uses precomputed presenceStatus field
        if (presenceFilter) {
            result = result.filter(a => a.presenceStatus === presenceFilter);
        }

        // Queue filter — show agents who are a member of any selected queue
        if (selectedQueues.size > 0) {
            result = result.filter(a => {
                for (const qid of selectedQueues) {
                    if (queueMembers.get(qid)?.has(a.agentId)) return true;
                }
                return false;
            });
        }

        return result;
    }, [agents, debouncedSearch, presenceFilter, selectedQueues, queueMembers]);

    const sortedAgents = useMemo(
        () => sortAgents(filteredAgents, sortState),
        [filteredAgents, sortState],
    );

    // Rebuild on data change, sort, grouping, or ticker ticks
    const gridRows = useMemo((): GridRow[] => {
        if (!groupBy) return sortedAgents.map(data => ({ kind: 'agent', data }));

        // Accumulate groups preserving sort order within each group
        const groupMap = new Map<string, { presenceName: string; basePresenceStatus: number; members: IAgentStatusRecord[] }>();
        for (const agent of sortedAgents) {
            const key = groupBy === 'presence'
                ? (agent.presenceName || 'Unknown')
                : (agent.isLoggedIn ? 'Logged In' : 'Logged Out');
            if (!groupMap.has(key)) {
                groupMap.set(key, { presenceName: agent.presenceName, basePresenceStatus: agent.basePresenceStatus, members: [] });
            }
            groupMap.get(key)!.members.push(agent);
        }

        const rows: GridRow[] = [];
        for (const [groupKey, { presenceName, basePresenceStatus, members }] of groupMap) {
            rows.push({ kind: 'group-header', groupKey, label: groupKey, count: members.length, presenceName, basePresenceStatus });
            if (!collapsedGroups.has(groupKey)) {
                for (const data of members) rows.push({ kind: 'agent', data });
            }
        }
        return rows;
    }, [sortedAgents, groupBy, collapsedGroups]); // tick removed — component re-renders naturally when tick state changes

    // ── Virtual scroll calculations ────────────────────────────────────────
    // Compute per-row heights (agent rows + optional expanded detail panels)
    const cumulativeHeights = useMemo(() => {
        const cum: number[] = [0];
        for (const row of gridRows) {
            const h = row.kind === 'group-header'
                ? GROUP_ROW_HEIGHT
                : ROW_HEIGHT + (expandedRows.has(row.data.id) ? DETAIL_HEIGHT : 0);
            cum.push((cum[cum.length - 1] ?? 0) + h);
        }
        return cum;
    }, [gridRows, expandedRows]);

    const totalVirtualHeight = cumulativeHeights[cumulativeHeights.length - 1] ?? 0;

    // Binary search to find first visible row index
    const firstVisible = Math.max(0, binarySearchLeft(cumulativeHeights, scrollTop) - 1);
    const lastVisible  = Math.min(
        gridRows.length - 1,
        binarySearchLeft(cumulativeHeights, scrollTop + containerHeight),
    );
    const startIndex  = Math.max(0,                firstVisible - OVERSCAN);
    const endIndex    = Math.min(gridRows.length - 1, lastVisible  + OVERSCAN);
    const offsetTop    = cumulativeHeights[startIndex]    ?? 0;
    const offsetBottom = totalVirtualHeight - (cumulativeHeights[endIndex + 1] ?? totalVirtualHeight);
    const colSpan      = isAuthorized ? 4 : 3;

    // ── Render ─────────────────────────────────────────────────────────────
    return (
        <div className={styles.root} style={rootStyle}>

            {/* ── Title / header bar ──────────────────────────────────── */}
            <div className={styles.headerBar}>
                <Text className={styles.title}>Agent Presence</Text>
                <div className={styles.headerRight}>
                    {isRefreshing
                        ? <Spinner size="tiny" />
                        : lastUpdated && (
                            <Text className={styles.lastUpdatedText}>{formatLastUpdated(lastUpdated)}</Text>
                        )
                    }
                </div>
            </div>

            {/* ── Status summary ────────────────────────────────────────── */}
            {!isInitialLoad && !error && (
                <StatusSummaryBar
                    agents={agents}
                    activeFilter={presenceFilter}
                    onFilter={setPresenceFilter}
                />
            )}

            {/* ── Toolbar ───────────────────────────────────────────────── */}
            <div className={styles.toolbar}>
                <Input
                    className={styles.searchInput}
                    placeholder="Search agents…"
                    value={searchText}
                    onChange={(_: React.ChangeEvent<HTMLInputElement>, d: { value: string }) => setSearchText(d.value)}
                    contentBefore={<SearchIcon />}
                    appearance="outline"
                    size="small"
                />

                {/* Group By */}
                <Menu>
                    <MenuTrigger disableButtonEnhancement>
                        <Button appearance="subtle" size="small">
                            Group by: {groupBy ? GROUP_BY_LABELS[groupBy] : 'None'}
                        </Button>
                    </MenuTrigger>
                    <MenuPopover style={{ backgroundColor: '#ffffff', boxShadow: '0 4px 16px rgba(0,0,0,0.14)', border: '1px solid #c8c6c4' }}>
                        <MenuList>
                            <MenuItem onClick={() => { setGroupBy(null); setCollapsedGroups(new Set()); }}>None</MenuItem>
                            <MenuItem onClick={() => {
                                const keys = new Set(sortedAgents.map(a => a.presenceName || 'Unknown'));
                                setGroupBy('presence');
                                setCollapsedGroups(keys);
                            }}>Presence</MenuItem>
                            <MenuItem onClick={() => {
                                setGroupBy('loggedIn');
                                setCollapsedGroups(new Set(['Logged In', 'Logged Out']));
                            }}>Logged In</MenuItem>
                        </MenuList>
                    </MenuPopover>
                </Menu>

                <div className={styles.toolbarRight}>
                    <Text className={styles.countText}>
                        {filteredAgents.length} of {agents.length} agent{agents.length !== 1 ? 's' : ''}
                    </Text>

                    {/* Auto-refresh toggle */}
                    <div
                        className={styles.toggleWrapper}
                        onClick={() => setAutoRefresh(v => !v)}
                        title={autoRefresh ? 'Auto-refresh on (every 10s) — click to turn off' : 'Auto-refresh off — click to turn on'}
                        role="switch"
                        aria-checked={autoRefresh}
                    >
                        <span className={cx(styles.toggleTrack, autoRefresh ? styles.toggleTrackOn : '')}>
                            <span className={cx(styles.toggleThumb, autoRefresh ? styles.toggleThumbOn : '')} />
                        </span>
                        <span className={styles.toggleLabel}>Auto-refresh</span>
                    </div>

                    <Button
                        appearance="subtle"
                        size="small"
                        disabled={isRefreshing || isInitialLoad}
                        onClick={() => { void fetchAgentData(false); }}
                    >
                        Refresh
                    </Button>
                </div>
            </div>

            {/* ── Queue filter bar ──────────────────────────────────────── */}
            {!isInitialLoad && !error && (
                <div className={styles.queueBar}>
                    <span className={styles.queueBarLabel}><QueueIcon /> Queues:</span>

                    {/* Active queue pills */}
                    {[...selectedQueues].map(qid => {
                        const q = availableQueues.find(x => x.id === qid);
                        return (
                            <span key={qid} className={cx(styles.queuePill, styles.queuePillActive)}>
                                {q?.name ?? qid}
                                <button
                                    className={styles.queuePillRemove}
                                    onClick={() => setSelectedQueues(prev => { const n = new Set(prev); n.delete(qid); return n; })}
                                    aria-label={`Remove queue ${q?.name ?? qid}`}
                                >✕</button>
                            </span>
                        );
                    })}

                    {/* Add queue button */}
                    <button
                        className={styles.queuePickerBtn}
                        onClick={(e) => {
                            const rect = e.currentTarget.getBoundingClientRect();
                            setQueuePickerAnchor({ top: rect.bottom + 4, left: rect.left });
                            setQueuePickerOpen(v => !v);
                            setQueueSearch('');
                        }}
                    >
                        + {selectedQueues.size === 0 ? 'Filter by queue' : 'Add queue'}
                    </button>

                    {/* Loading indicator while fetching members */}
                    {queueFilterLoading && (
                        <span style={{ fontSize: '12px', color: '#605e5c', marginLeft: '4px' }}>
                            ⏳ Loading…
                        </span>
                    )}

                    {/* Clear all */}
                    {selectedQueues.size > 0 && (
                        <button
                            className={styles.queuePickerBtn}
                            style={{ borderStyle: 'solid', color: '#a4262c', borderColor: '#a4262c' }}
                            onClick={() => setSelectedQueues(new Set())}
                        >
                            Clear
                        </button>
                    )}
                </div>
            )}

            {/* ── Queue picker dropdown ──────────────────────────────────── */}
            {queuePickerOpen && queuePickerAnchor && (
                <>
                    <div
                        style={{ position: 'fixed', inset: '0', zIndex: 1999 }}
                        onClick={() => setQueuePickerOpen(false)}
                    />
                    <div
                        className={styles.queueDropdown}
                        style={{ top: queuePickerAnchor.top, left: queuePickerAnchor.left }}
                        onClick={e => e.stopPropagation()}
                    >
                        <div className={styles.queueDropdownSearch}>
                            <Input
                                size="small"
                                appearance="outline"
                                placeholder="Search queues…"
                                value={queueSearch}
                                onChange={(_: React.ChangeEvent<HTMLInputElement>, d: { value: string }) => setQueueSearch(d.value)}
                                contentBefore={<SearchIcon />}
                                style={{ width: '100%' }}
                            />
                        </div>
                        <div className={styles.queueDropdownList}>
                            {availableQueues.length === 0 ? (
                                <div className={styles.queueDropdownEmpty}>No queues found</div>
                            ) : (() => {
                                const filtered = queueSearch.trim()
                                    ? availableQueues.filter(q => q.name.toLowerCase().includes(queueSearch.toLowerCase()))
                                    : availableQueues;
                                if (filtered.length === 0) return (
                                    <div className={styles.queueDropdownEmpty}>No queues match your search</div>
                                );
                                return filtered.map(q => {
                                    const isChecked = selectedQueues.has(q.id);
                                    const memberCount = isChecked ? (queueMembers.get(q.id)?.size ?? 0) : undefined;
                                    return (
                                        <div
                                            key={q.id}
                                            className={cx(styles.queueDropdownItem, isChecked ? styles.queueDropdownItemChecked : '')}
                                            onClick={() => {
                                                setSelectedQueues(prev => {
                                                    const n = new Set(prev);
                                                    if (n.has(q.id)) n.delete(q.id); else n.add(q.id);
                                                    return n;
                                                });
                                            }}
                                        >
                                            <span style={{ fontSize: '14px' }}>{isChecked ? '☑' : '☐'}</span>
                                            <span style={{ flex: '1' }}>{q.name}</span>
                                            {isChecked && !queueFilterLoading && memberCount !== undefined && (
                                                <span style={{ fontSize: '11px', color: '#a19f9d' }}>{memberCount} agents</span>
                                            )}
                                        </div>
                                    );
                                });
                            })()}
                        </div>
                    </div>
                </>
            )}

            {/* ── Content ───────────────────────────────────────────────── */}
            {isInitialLoad ? (
                <div className={styles.loadingState}>
                    <Spinner size="medium" label="Loading agent presence data…" />
                </div>

            ) : error ? (
                <div className={styles.errorState}>
                    <Text>{error}</Text>
                    <Button appearance="primary" size="small" onClick={() => { void fetchAgentData(false); }}>Retry</Button>
                </div>

            ) : (
                <div
                    className={styles.tableContainer}
                    ref={tableContainerRef}
                    onScroll={(e) => setScrollTop((e.currentTarget as HTMLDivElement).scrollTop)}
                >
                    <table className={styles.table}>
                        {/* colgroup: expander | Agent (flex) | Action | Presence */}
                        <colgroup>
                            <col style={{ width: '32px' }} />
                            <col />
                            {isAuthorized && <col style={{ width: '84px' }} />}
                            <col style={{ width: '80px' }} />
                        </colgroup>
                        <thead className={styles.thead}>
                            <tr>
                                <th className={styles.th} style={{ cursor: 'default', padding: '8px 0 8px 8px' }} />
                                <ColHeader label="Agent"    colId="agentName" sortState={sortState} onSort={handleSort} />
                                {isAuthorized && <th className={styles.th} style={{ cursor: 'default', padding: '8px 4px' }} />}
                                <ColHeader label="Presence" colId="presence"  sortState={sortState} onSort={handleSort} extraClass={cx(styles.thPresence)} />
                            </tr>
                        </thead>

                        <tbody>
                            {gridRows.length === 0 ? (
                                <tr>
                                    <td colSpan={colSpan} className={styles.emptyStateTd}>
                                        <Text>{searchText ? 'No agents match your search.' : 'No agent data available.'}</Text>
                                    </td>
                                </tr>
                            ) : (
                                <>
                                    {/* Top virtual spacer */}
                                    {offsetTop > 0 && (
                                        <tr aria-hidden="true">
                                            <td colSpan={colSpan} style={{ height: offsetTop, padding: 0, border: 'none' }} />
                                        </tr>
                                    )}

                                    {gridRows.slice(startIndex, endIndex + 1).map((row) => {

                                        if (row.kind === 'group-header') {
                                            const isCollapsed = collapsedGroups.has(row.groupKey);
                                            return (
                                                <tr
                                                    key={`gh-${row.groupKey}`}
                                                    className={styles.groupHeaderTr}
                                                    onClick={() => toggleGroup(row.groupKey)}
                                                >
                                                    <td className={styles.groupHeaderTd} colSpan={colSpan}>
                                                        <div className={styles.groupHeaderContent}>
                                                            {isCollapsed ? <ChevronRightIcon /> : <ChevronDownIcon />}
                                                            {groupBy === 'presence' && (
                                                                <PresenceIcon
                                                                    presenceName={row.presenceName}
                                                                    basePresenceStatus={row.basePresenceStatus}
                                                                    size={16}
                                                                />
                                                            )}
                                                            <span>{row.label}</span>
                                                            <span className={styles.groupCount}>({row.count})</span>
                                                        </div>
                                                    </td>
                                                </tr>
                                            );
                                        }

                                        const agent      = row.data;
                                        const isExpanded = expandedRows.has(agent.id);
                                        const isEditing  = editingAgentId === agent.id;
                                        return (
                                            <React.Fragment key={agent.id}>
                                                {/* ── Agent row ── */}
                                                <tr
                                                    className={styles.tr}
                                                    onMouseEnter={() => setHoveredRowId(agent.id)}
                                                    onMouseLeave={() => setHoveredRowId(prev => prev === agent.id ? null : prev)}
                                                >
                                                    <td className={styles.tdExpander}>
                                                        <button
                                                            className={styles.expanderBtn}
                                                            onClick={() => toggleExpand(agent)}
                                                            aria-label={isExpanded ? 'Collapse' : 'Expand'}
                                                            title={isExpanded ? 'Collapse' : 'Expand'}
                                                        >
                                                            {isExpanded ? <ChevronDownIcon /> : <ChevronRightIcon />}
                                                        </button>
                                                    </td>
                                                    <td className={styles.td}>
                                                        <span className={styles.agentName}>{agent.agentName}</span>
                                                    </td>
                                                    {isAuthorized && (
                                                        <td className={styles.tdAction}>
                                                            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px', height: '100%' }}>
                                                                <button
                                                                    className={cx(styles.editBtn, (isEditing || hoveredRowId === agent.id) ? styles.editBtnVisible : '')}
                                                                    title="View presence history"
                                                                    aria-label={`View presence history for ${agent.agentName}`}
                                                                    onClick={(e) => {
                                                                        e.stopPropagation();
                                                                        // Reset any stale data before opening for this agent
                                                                        setHistoryModalData({ days: [], loading: false, error: null });
                                                                        setHistoryModalAgent(agent);
                                                                        fetchHistoryModal(agent);
                                                                    }}
                                                                >
                                                                    <HistoryIcon />
                                                                </button>
                                                                <button
                                                                    data-edit-btn
                                                                    className={cx(
                                                                        styles.editBtn,
                                                                        agent.presenceStatus === 'offline'
                                                                            ? styles.editBtnDisabled
                                                                            : (isEditing || hoveredRowId === agent.id) ? styles.editBtnVisible : ''
                                                                    )}
                                                                    title={agent.presenceStatus === 'offline' ? 'Cannot change presence for offline agents' : 'Change presence'}
                                                                    aria-label={agent.presenceStatus === 'offline' ? `${agent.agentName} is offline — presence cannot be changed` : `Change presence for ${agent.agentName}`}
                                                                    disabled={agent.presenceStatus === 'offline'}
                                                                    onClick={(e) => {
                                                                        e.stopPropagation();
                                                                        if (isEditing) { closePicker(); } else { openPicker(agent.id); }
                                                                    }}
                                                                >
                                                                    <PencilIcon />
                                                                </button>
                                                            </div>
                                                        </td>
                                                    )}
                                                    <td className={cx(styles.td, styles.tdPresence)}>
                                                        <PresenceIcon
                                                            presenceName={agent.presenceName}
                                                            basePresenceStatus={agent.basePresenceStatus}
                                                            size={20}
                                                        />
                                                    </td>
                                                </tr>

                                                {/* ── Expanded detail row ── */}
                                                {isExpanded && (
                                                    <tr className={styles.trDetail}>
                                                        <td colSpan={colSpan} className={styles.tdDetail}>
                                                            {/* ── Summary fields ── */}
                                                            <div className={styles.detailPanel}>
                                                                <div className={styles.detailField}>
                                                                    <span className={styles.detailLabel}>Presence</span>
                                                                    <span className={styles.detailValue}>{agent.presenceName || '—'}</span>
                                                                </div>
                                                                <div className={styles.detailField}>
                                                                    <span className={styles.detailLabel}>Logged In</span>
                                                                    <span className={styles.detailValue}>
                                                                        <Badge
                                                                            color={agent.isLoggedIn ? 'success' : 'subtle'}
                                                                            appearance={agent.isLoggedIn ? 'filled' : 'outline'}
                                                                        >
                                                                            {agent.isLoggedIn ? 'Yes' : 'No'}
                                                                        </Badge>
                                                                    </span>
                                                                </div>
                                                                <div className={styles.detailField}>
                                                                    <span className={styles.detailLabel}>Time In Presence</span>
                                                                    <span className={styles.detailValue}>{formatDuration(agent.startTime)}</span>
                                                                </div>
                                                                {agent.startTime && (
                                                                    <div className={styles.detailField}>
                                                                        <span className={styles.detailLabel}>Since</span>
                                                                        <span className={styles.detailValue}>
                                                                            {agent.startTime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                                                                        </span>
                                                                    </div>
                                                                )}
                                                            </div>

                                                            {/* ── Presence history timeline (last 24h) ── */}
                                                            <div className={styles.historySection}>
                                                                <div className={styles.historySectionTitle}>
                                                                    <span>Presence History — Last 24 Hours</span>
                                                                    <button
                                                                        className={styles.historyRefreshBtn}
                                                                        title="Refresh history"
                                                                        aria-label="Refresh presence history"
                                                                        onClick={(e) => { e.stopPropagation(); fetchHistory(agent); }}
                                                                        disabled={historyMap.get(agent.agentId)?.loading === true}
                                                                    >
                                                                        <RefreshIcon size={13} />
                                                                    </button>
                                                                </div>
                                                                <HistoryTimeline
                                                                    history={historyMap.get(agent.agentId) ?? { entries: [], loading: true, error: null }}
                                                                />
                                                            </div>
                                                        </td>
                                                    </tr>
                                                )}
                                            </React.Fragment>
                                        );
                                    })}

                                    {/* Bottom virtual spacer */}
                                    {offsetBottom > 0 && (
                                        <tr aria-hidden="true">
                                            <td colSpan={colSpan} style={{ height: offsetBottom, padding: 0, border: 'none' }} />
                                        </tr>
                                    )}
                                </>
                            )}
                        </tbody>
                    </table>
                </div>
            )}

            {/* ── Presence picker modal ────────────────────────────────── */}
            {isAuthorized && editingAgentId && (() => {
                const agent = agents.find(a => a.id === editingAgentId);
                return (
                    <div className={styles.pickerOverlay} onClick={closePicker}>
                        <div
                            className={styles.picker}
                            onClick={(e) => e.stopPropagation()}
                        >
                            {/* Header */}
                            <div className={styles.pickerHeader}>
                                <span className={styles.pickerHeaderTitle}>Set Presence</span>
                                <button className={styles.pickerCloseBtn} onClick={closePicker} aria-label="Close">✕</button>
                            </div>

                            {/* Agent name subtitle */}
                            <div className={styles.pickerSubtitle}>{agent?.agentName ?? ''}</div>

                            {/* Presence list */}
                            {isSaving ? (
                                <div className={styles.pickerSaving}>
                                    <Spinner size="small" /> Updating presence…
                                </div>
                            ) : (
                                <div className={styles.pickerList}>
                                    {availablePresences.map(p => (
                                        <div
                                            key={p.id}
                                            className={cx(
                                                styles.pickerItem,
                                                agent?.presenceId === p.id ? styles.pickerItemActive : '',
                                            )}
                                            onClick={() => { void modifyPresence(agent?.agentId ?? '', p.id); }}
                                        >
                                            <PresenceIcon presenceName={p.name} basePresenceStatus={p.basePresenceStatus} size={18} />
                                            <span>{p.name}</span>
                                        </div>
                                    ))}
                                </div>
                            )}
                            {saveError && <div className={styles.pickerError}>{saveError}</div>}
                            <div className={styles.pickerNote}>
                                <svg width="13" height="13" viewBox="0 0 16 16" fill="#605e5c" style={{ flexShrink: 0, marginTop: '1px' }}>
                                    <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zm0 3.25a.875.875 0 1 1 0 1.75.875.875 0 0 1 0-1.75zM7.25 7h1.5v4.5h-1.5V7z"/>
                                </svg>
                                <span>Omnichannel Administrator Role is needed to perform this action.</span>
                            </div>
                        </div>
                    </div>
                );
            })()}

            {/* ── Agent History Modal ──────────────────────────────────── */}
            {historyModalAgent && (
                <AgentHistoryModal
                    agent={historyModalAgent}
                    data={historyModalData}
                    onClose={() => {
                        historyModalAgentIdRef.current = '';
                        setHistoryModalAgent(null);
                        setHistoryModalData({ days: [], loading: false, error: null });
                    }}
                    onRefresh={() => fetchHistoryModal(historyModalAgent)}
                />
            )}

            {/* ── Footer: Rows count ────────────────────────────────── */}
            {!isInitialLoad && !error && (
                <div className={styles.footer}>
                    Rows: {filteredAgents.length}
                </div>
            )}
        </div>
    );
};

export default AgentPresenceGrid;
