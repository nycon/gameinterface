/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        panel: {
          bg: '#0f1419',
          surface: '#161d26',
          border: '#252f3d',
          muted: '#6b7a8f',
          text: '#c8d0dc',
          accent: '#e8a838',
          'accent-hover': '#f0b84a',
          danger: '#e05252',
          success: '#3dba6a',
          warning: '#d4a017',
        },
      },
      fontFamily: {
        sans: ['"IBM Plex Sans"', 'system-ui', 'sans-serif'],
        mono: ['"IBM Plex Mono"', 'monospace'],
      },
    },
  },
  plugins: [],
}
