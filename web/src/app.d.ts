// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
declare global {
	namespace App {
		// interface Error {}
		// interface Locals {}
		// interface PageData {}
		// interface PageState {}
		// interface Platform {}
	}

	// Global window object type extensions
	interface Window {
		Engine: typeof Engine;
		WebHelper: typeof WebHelper;
	}

	// Godot Engine types
	interface EngineConfig {
		args?: string[];
		canvasResizePolicy?: number;
		ensureCrossOriginIsolationHeaders?: boolean;
		executable?: string;
		experimentalVK?: boolean;
		fileSizes?: Record<string, number>;
		focusCanvas?: boolean;
		gdextensionLibs?: string[];
		serviceWorker?: string;
	}

	interface EngineStartOptions {
		canvas: HTMLCanvasElement;
		onPrint?: (text: string) => void;
		onPrintError?: (text: string) => void;
		onProgress?: (current: number, total: number) => void;
	}

	interface EngineFeatureCheck {
		threads?: boolean;
	}

	declare class Engine {
		constructor(config: EngineConfig);
		static getMissingFeatures(features: EngineFeatureCheck): string[];
		startGame(options: EngineStartOptions): Promise<void>;
	}

	// Make Engine available globally
	declare const Engine: typeof Engine;

	declare class WebHelper {
		static getCurrentRegisters(): Record<"pc" | "a" | "x" | "y" | "p" | "sp", number>;
		static nextShip(): void;
		static previousShip(): void;
		static getPage(page: number): ArrayBuffer;
	}

	declare const WebHelper: typeof WebHelper;
}

export {};
