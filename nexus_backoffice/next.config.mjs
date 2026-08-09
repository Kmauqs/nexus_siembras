/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Las fotos de patologías viven en Supabase Storage.
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: '*.supabase.co' },
    ],
  },
};

export default nextConfig;
