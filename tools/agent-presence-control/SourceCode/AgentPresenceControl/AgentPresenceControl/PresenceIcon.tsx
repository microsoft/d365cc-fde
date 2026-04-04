/* eslint-disable react/prop-types */
import * as React from 'react';
import { Tooltip } from '@fluentui/react-components';

export type PresenceStatus =
    | 'available'
    | 'busy'
    | 'donotdisturb'
    | 'berightback'
    | 'away'
    | 'offline'
    | 'unknown';

/** Maps a Dataverse msdyn_presence name / base status integer to a PresenceStatus.
 *  msdyn_basepresencestatus option set values (from docs):
 *  192360000 = Available | 192360001 = Busy | 192360002 = Busy-DND
 *  192360003 = Away      | 192360004 = Offline
 */
export function resolvePresenceStatus(presenceName: string, baseStatus?: number): PresenceStatus {
    if (baseStatus !== undefined && baseStatus !== null) {
        const map: Record<number, PresenceStatus> = {
            192360000: 'available',
            192360001: 'busy',
            192360002: 'donotdisturb',
            192360003: 'away',
            192360004: 'offline',
        };
        if (map[baseStatus]) return map[baseStatus];
    }

    // Name-based fallback for custom presence entries
    const name = (presenceName ?? '').toLowerCase().trim();
    if (name.includes('available'))                              return 'available';
    if (name.includes('do not disturb') || name === 'dnd')      return 'donotdisturb';
    if (name.includes('busy') || name.includes('in a call')
        || name.includes('in a meeting'))                        return 'busy';
    if (name.includes('be right back') || name === 'brb')        return 'berightback';
    if (name.includes('away'))                                    return 'away';
    if (name.includes('offline'))                                 return 'offline';
    return 'unknown';
}

export const PRESENCE_LABELS: Record<PresenceStatus, string> = {
    available:    'Available',
    busy:         'Busy',
    donotdisturb: 'Do Not Disturb',
    berightback:  'Be Right Back',
    away:         'Away',
    offline:      'Offline',
    unknown:      'Unknown',
};

interface IPresenceIconProps {
    presenceName: string;
    basePresenceStatus?: number;
    size?: number;
}

/**
 * Teams-style presence icon rendered as inline SVG.
 * Wrapped in a Fluent UI Tooltip showing the presence label.
 */
export const PresenceIcon: React.FC<IPresenceIconProps> = React.memo(({
    presenceName,
    basePresenceStatus,
    size = 20,
}) => {
    const status = resolvePresenceStatus(presenceName, basePresenceStatus);
    const label  = presenceName || PRESENCE_LABELS[status];

    return (
        <Tooltip content={label} relationship="description" withArrow>
            <span style={{ display: 'inline-flex', alignItems: 'center', cursor: 'default' }}>
                {renderPresenceSvg(status, size)}
            </span>
        </Tooltip>
    );
});
PresenceIcon.displayName = 'PresenceIcon';

function renderPresenceSvg(status: PresenceStatus, size: number): React.ReactElement {
    switch (status) {
        case 'available':
            // Solid green circle with a white checkmark
            return (
                <svg width={size} height={size} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <circle cx="10" cy="10" r="9" fill="#6BB700" />
                    <path d="M6 10.5L8.5 13L14 7.5" stroke="white" strokeWidth="1.8"
                        strokeLinecap="round" strokeLinejoin="round" />
                </svg>
            );

        case 'busy':
            // Solid red circle
            return (
                <svg width={size} height={size} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <circle cx="10" cy="10" r="9" fill="#C50F1F" />
                </svg>
            );

        case 'donotdisturb':
            // Red circle with a white horizontal bar (Teams DND style)
            return (
                <svg width={size} height={size} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <circle cx="10" cy="10" r="9" fill="#C50F1F" />
                    <rect x="5" y="8.75" width="10" height="2.5" rx="1.25" fill="white" />
                </svg>
            );

        case 'berightback':
            // Yellow circle with a white return-arrow
            return (
                <svg width={size} height={size} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <circle cx="10" cy="10" r="9" fill="#FFAA44" />
                    <path d="M13.5 7.5C12.3 6 10.8 5 9 5C6 5 3.5 7.5 3.5 10.5S6 16 9 16"
                        stroke="white" strokeWidth="1.6" strokeLinecap="round" fill="none" />
                    <path d="M13 6L16 8.5L13 10"
                        stroke="white" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" fill="none" />
                </svg>
            );

        case 'away':
            // Yellow circle with a white clock hand (Teams Away style)
            return (
                <svg width={size} height={size} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <circle cx="10" cy="10" r="9" fill="#FFAA44" />
                    <path d="M10 5.5V10.5L13 13" stroke="white" strokeWidth="1.6"
                        strokeLinecap="round" strokeLinejoin="round" />
                </svg>
            );

        case 'offline':
            // Grey filled circle with a white diagonal slash — matches Teams Offline style
            return (
                <svg width={size} height={size} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <circle cx="10" cy="10" r="9" fill="#8A8886" />
                    <line x1="5.5" y1="14.5" x2="14.5" y2="5.5" stroke="white" strokeWidth="2" strokeLinecap="round" />
                </svg>
            );

        default:
            // Faded grey circle for unknown / no presence
            return (
                <svg width={size} height={size} viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <circle cx="10" cy="10" r="9" fill="#8A8886" opacity="0.35" />
                </svg>
            );
    }
}
