/// OpenF1 `circuit_key` to the vendored circuit id (bacinger/f1-circuits).
///
/// Covers every venue raced from 2023. Madrid (153) and Sepang (12) are
/// missing: upstream has their layouts but no start/finish or sector markers
/// yet.
const Map<int, String> circuitIdByOpenF1Key = {
  2: 'gb-1948', // Silverstone
  4: 'hu-1986', // Hungaroring
  6: 'it-1953', // Imola
  7: 'be-1925', // Spa-Francorchamps
  9: 'us-2012', // Austin
  10: 'au-1953', // Melbourne
  14: 'br-1940', // Interlagos
  15: 'es-1991', // Catalunya
  19: 'at-1969', // Spielberg
  22: 'mc-1929', // Monte Carlo
  23: 'ca-1978', // Montreal
  39: 'it-1922', // Monza
  46: 'jp-1962', // Suzuka
  49: 'cn-2004', // Shanghai
  55: 'nl-1948', // Zandvoort
  61: 'sg-2008', // Singapore
  63: 'bh-2002', // Sakhir
  65: 'mx-1962', // Mexico City
  70: 'ae-2009', // Yas Marina
  144: 'az-2016', // Baku
  149: 'sa-2021', // Jeddah
  150: 'qa-2004', // Lusail
  151: 'us-2022', // Miami
  152: 'us-2023', // Las Vegas
};
