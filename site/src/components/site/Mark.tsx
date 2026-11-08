// The Oatmeal mark: the wave-loop on an umber tile, and the bare wave-loop for small or dark spots.

const LOOP =
  'M5800 6665c-8-2-49-9-90-15-572-91-1251-644-1541-1255-220-465-246-907-72-1247 25-48 41-92 37-99-10-16-93-6-179 23-239 79-397 242-666 688-161 266-242 382-339 480-305 308-700 304-1043-11-38-34-133-137-211-228-238-277-268-293-546-301-188-5-197-6-252-33-230-113-198-441 49-513 75-22 377-15 468 11 216 61 370 180 622 480 197 235 277 295 396 295 147 0 197-51 425-433 260-434 432-640 662-791 316-208 614-242 1176-133l219 42 2205 5c2205 5 2205 5 2245 27 182 98 177 357-9 456-41 22-41 22-1663 25-1075 1-1623 6-1623 12 0 6 73 83 163 173 408 408 621 805 659 1230 47 527-212 947-669 1083-76 23-110 27-248 30-88 1-167 1-175-1zm333-524c321-127 314-635-17-1144-267-412-735-811-1052-898-432-118-699 300-532 831 168 533 736 1093 1238 1220 108 28 282 23 363-9z'

export function Mark({ size = 28, className = '' }: { size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 1024 1024" className={className} aria-hidden>
      <rect width="1024" height="1024" rx="232" fill="#4A3426" />
      <g transform="translate(0 1024) scale(0.1 -0.1)">
        <path fill="#E8DCC4" d={LOOP} />
      </g>
    </svg>
  )
}

export function Loop({ width = 22, color = 'currentColor', className = '' }: { width?: number; color?: string; className?: string }) {
  return (
    <svg width={width} height={(width * 340) / 940} viewBox="40 330 940 340" className={className} aria-hidden>
      <g transform="translate(0 1024) scale(0.1 -0.1)">
        <path fill={color} d={LOOP} />
      </g>
    </svg>
  )
}

export function AppleLogo({ size = 16, className = '' }: { size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" className={className} aria-hidden>
      <path
        fill="currentColor"
        d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"
      />
    </svg>
  )
}
