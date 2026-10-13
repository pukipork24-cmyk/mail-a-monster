--!strict
export type State = "HOME" | "LAUNCH_PENDING" | "QUEUED" | "HELD" | "RETURNING"
export type Settings = { reducedMotion: boolean, musicVolume: number, sfxVolume: number, cameraShake: boolean, shareCountry: boolean, acceptVisitors: boolean }
export type Event = { kind: string, at: number, label: string, souvenirId: string?, stampId: string?, country: string?, humanHop: boolean?, rewardEligible: boolean? }
export type Intent = { [string]: string | number | boolean }
export type Response = { ok: boolean, error: string?, data: any?, effect: any? }
return {}
