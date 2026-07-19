module.exports = function (api) {
  api.cache(true);
  return {
    presets: ['babel-preset-expo'],
    // react-native-worklets/plugin deve ser sempre o último.
    plugins: ['react-native-worklets/plugin'],
  };
};
