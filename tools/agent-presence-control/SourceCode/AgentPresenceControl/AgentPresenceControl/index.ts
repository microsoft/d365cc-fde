import { IInputs, IOutputs } from "./generated/ManifestTypes";
import AgentPresenceGrid from "./AgentPresenceGrid";
import * as React from "react";

export class AgentPresenceControl implements ComponentFramework.ReactControl<IInputs, IOutputs> {
    private notifyOutputChanged: () => void;

    constructor() { /* empty */ }

    public init(
        context: ComponentFramework.Context<IInputs>,
        notifyOutputChanged: () => void,
        _state: ComponentFramework.Dictionary,
    ): void {
        this.notifyOutputChanged = notifyOutputChanged;
        // Tell PCF we want to be notified when the container is resized
        context.mode.trackContainerResize(true);
    }

    /**
     * Called by PCF on every context change including container resize.
     * Pass allocatedWidth/Height so the component can fill available space.
     */
    public updateView(context: ComponentFramework.Context<IInputs>): React.ReactElement {
        const width  = context.mode.allocatedWidth  > 0 ? context.mode.allocatedWidth  : undefined;
        const height = context.mode.allocatedHeight > 0 ? context.mode.allocatedHeight : undefined;
        return React.createElement(AgentPresenceGrid, {
            webAPI: context.webAPI,
            userId: context.userSettings.userId,
            width,
            height,
        });
    }

    public getOutputs(): IOutputs {
        return {};
    }

    public destroy(): void { /* nothing to clean up at the PCF level */ }
}
