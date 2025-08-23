export class AppState {
    isPaused = $state(false);
    frequency = $state(10);
    code = $state('');
    shipIdx = $state(0);

    setFrequency(frequency: number) {
        this.frequency = frequency;
    }
    togglePause() {
        this.isPaused = !this.isPaused;
    }

    async goToShip(idx: number) {
        this.shipIdx = idx;
        const { code, isPaused, frequency } = await window.WebHelper.getState();
        this.code = code;
        this.isPaused = isPaused;
        this.frequency = frequency;
    }

    async nextShip() {
        this.goToShip(this.shipIdx + 1);
    }

    async previousShip() {
        this.goToShip(this.shipIdx - 1);
    }
}

export const appState = new AppState();