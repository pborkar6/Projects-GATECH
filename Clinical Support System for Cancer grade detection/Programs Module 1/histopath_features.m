function [ output_features ] = histopath_features( input_regions, input_image )
%HISTOPATH_FEATURES
%   Given the nuclei regions of a histopathology image,
%   this function extracts the corresponding features.

[M, N, ~] = size(input_image);

if ((M ~= input_regions.ImageSize(1)) || ...
    (N ~= input_regions.ImageSize(2)))
    error('Input image size must match total size of regions');
end

region_indices = zeros(0, 1);

region_stats = regionprops(input_regions, ...
                           'Centroid', ...
                           'Area', ...
                           'MajorAxisLength', ...
                           'MinorAxisLength', ...
                           'EquivDiameter', ...
                           'Orientation', ...
                           'Perimeter', ...
                           'Solidity');

for i = 1:length(region_stats)
    % Only extract features from regions larger than 9 pixels;
    % this ensures that small regions that contain very little information
    % are ignored
    if (region_stats(i).Area >= 9)
        region_indices = [region_indices; i];
    end
end

if (isempty(region_indices))
    error('No regions to extract features from!');
end

centroids        = zeros(length(region_indices), 2);
areas            = zeros(length(region_indices), 1);
majoraxislengths = zeros(length(region_indices), 1);
minoraxislengths = zeros(length(region_indices), 1);
equivdiameters   = zeros(length(region_indices), 1);
eccentricity     = zeros(length(region_indices), 1);
orientation      = zeros(length(region_indices), 1);
perimeters       = zeros(length(region_indices), 1);
solidity         = zeros(length(region_indices), 1);
alignedness      = zeros(length(region_indices), 1);
crowdedness      = zeros(length(region_indices), 1);
regioncoloravg   = zeros(length(region_indices), 3);
regioncolorstdev = zeros(length(region_indices), 3);
regiongrayavg    = zeros(length(region_indices), 1);
regiongraystdev  = zeros(length(region_indices), 1);

for i = 1:length(region_indices)
    centroids(i, :)     = region_stats(region_indices(i)).Centroid;
    areas(i)            = region_stats(region_indices(i)).Area;
    majoraxislengths(i) = region_stats(region_indices(i)).MajorAxisLength;
    minoraxislengths(i) = region_stats(region_indices(i)).MinorAxisLength;
    equivdiameters(i)   = region_stats(region_indices(i)).EquivDiameter;
    % Get eccentricity as "second flattening";
    % "second flattening" is used because it is linear in the major axis
    % which provides a more intuitive way to calculate the "alignedness"
    eccentricity(i)     = (majoraxislengths(i) - minoraxislengths(i)) ./ ...
                          minoraxislengths(i);
    % Get orientation in radians from 0 to pi
    orientation(i)      = (pi / 180) * ...
                          region_stats(region_indices(i)).Orientation;
    orientation(i)      = (orientation(i) >= 0) .*  orientation(i) + ...
                          (orientation(i) <  0) .* (orientation(i) + pi);
    perimeters(i)       = region_stats(region_indices(i)).Perimeter;
    solidity(i)         = region_stats(region_indices(i)).Solidity;
end

compactness = 4 * pi * areas ./ (perimeters .^ 2);

[voronoi_vertices, voronoi_cells] = voronoin(centroids);

for i = 1:length(region_indices)
    voronoi_vertices_i = zeros(0, 2);
    for j = 1:length(voronoi_cells{i})
        if (any(isinf(voronoi_vertices(voronoi_cells{i}(j), :))))
            crowdedness(i) = NaN;
            break;
        end
        voronoi_vertices_i = [voronoi_vertices_i; ...
                              voronoi_vertices(voronoi_cells{i}(j), :)];
    end
    if (isnan(crowdedness(i)) || ...
        (size(voronoi_vertices, 1) < 3))
        crowdedness(i) = NaN;
    else
        [~, voronoi_area] = convhulln(voronoi_vertices_i);
        crowdedness(i) = areas(i) / voronoi_area;
    end
end

triangulation = delaunayTriangulation(centroids);

for i = 1:length(region_indices)
    neighbors_i = isConnected(triangulation, ...
                              i .* ones(length(region_indices), 1), ...
                              (1:length(region_indices))');
    if (sum(neighbors_i) <= 0)
        alignedness(i) = NaN;
    else
        neighbors_i_eccentricity = eccentricity(neighbors_i);
        neighbors_i_orientation  = orientation(neighbors_i);
        alignedness(i) = calculate_alignedness([eccentricity(i), ...
                                                orientation(i)], ...
                                               [neighbors_i_eccentricity, ...
                                                neighbors_i_orientation]);
    end
end

delaunayedges = edges(triangulation);

delaunaydistances = sqrt((centroids(delaunayedges(:, 1), 1) - ...
                          centroids(delaunayedges(:, 2), 1)).^2 + ...
                         (centroids(delaunayedges(:, 1), 2) - ...
                          centroids(delaunayedges(:, 2), 2)).^2);

normdistancesmajoraxis = delaunaydistances ./ ...
                         mean(majoraxislengths, 'omitnan');

normdistancesequivdiameter = delaunaydistances ./ ...
                             mean(equivdiameters, 'omitnan');

for i = 1:length(region_indices)
    [k, l] = ind2sub([M, N], input_regions.PixelIdxList{region_indices(i)});
    regionpixels = zeros(length(k), size(input_image, 3));
    for j = 1:length(k)
        regionpixels(j, :) = double(input_image(k(j), l(j), :));
    end
    if (size(regionpixels, 2) ~= 3)
        % Ensure exactly three channels
        regionpixels = [regionpixels(:, 1), ...
                        regionpixels(:, 1), ...
                        regionpixels(:, 1)];
    end
    regioncoloravg(i, 1) = mean(regionpixels(:, 1), 'omitnan');
    regioncoloravg(i, 2) = mean(regionpixels(:, 2), 'omitnan');
    regioncoloravg(i, 3) = mean(regionpixels(:, 3), 'omitnan');
    regioncolorstdev(i, 1) = std(regionpixels(:, 1), 'omitnan');
    regioncolorstdev(i, 2) = std(regionpixels(:, 2), 'omitnan');
    regioncolorstdev(i, 3) = std(regionpixels(:, 3), 'omitnan');
    regiongrayavg(i) = mean((regionpixels(:, 1) + ...
                             regionpixels(:, 2) + ...
                             regionpixels(:, 3)) ./ 3, ...
                             'omitnan');
    regiongraystdev(i) = std((regionpixels(:, 1) + ...
                              regionpixels(:, 2) + ...
                              regionpixels(:, 3)) ./ 3, ...
                              'omitnan');
end

grayimage = (double(input_image(:, :, 1)) + ...
             double(input_image(:, :, 2)) + ...
             double(input_image(:, :, 3)))./3;

gaborarray = gabor([4,   8,  12,  16,  20,  24,  28,  32], ...
                   [0,  18,  36,  54,  72,  90, 108, 126, 144, 162]);

gabormag = imgaborfilt(grayimage, gaborarray);

gaboravg_avg = zeros(8, 1);
gaborstd_avg = zeros(8, 1);
gaboravg_std = zeros(8, 1);
gaborstd_std = zeros(8, 1);

for i = 1:8
    % Iterate over each gabor-wavelength
    gaboravg = zeros(10, 1);
    gaborstd = zeros(10, 1);
    for j = 1:10
        % Iterate over each gabor-orientation
        p = i + (j-1) * 8;
        % Take mean of intensity of all gabor-filtered pixels
        gaboravg(j) = mean(reshape(gabormag(:, :, p), [M * N, 1]));
        % Take standard deviation of intensity of all gabor-filtered pixels
        gaborstd(j) = std(reshape(gabormag(:, :, p), [M * N, 1]));
    end
    % Take mean of
    % intensity mean over all orientations
    gaboravg_avg(i) = mean(gaboravg);
    % Take mean of
    % intensity standard deviation over all orientations
    gaborstd_avg(i) = mean(gaborstd);
    % Take standard deviation of
    % intensity mean over all orientations
    gaboravg_std(i) = std(gaboravg);
    % Take standard deviation of
    % intensity standard deviation over all orientations
    gaborstd_std(i) = std(gaborstd);
end

glcm_features = haralick_features(input_image);

features = [distribution_parameters(areas), ...
            distribution_parameters(majoraxislengths), ...
            distribution_parameters(equivdiameters), ...
            distribution_parameters(eccentricity), ...
            distribution_parameters(solidity), ...
            distribution_parameters(compactness), ...
            distribution_parameters(crowdedness), ...
            distribution_parameters(alignedness), ...
            distribution_parameters(delaunaydistances), ...
            distribution_parameters(normdistancesmajoraxis), ...
            distribution_parameters(normdistancesequivdiameter), ...
            distribution_parameters(regioncoloravg(:, 1)), ...
            distribution_parameters(regioncoloravg(:, 2)), ...
            distribution_parameters(regioncoloravg(:, 3)), ...
            distribution_parameters(regioncolorstdev(:, 1)), ...
            distribution_parameters(regioncolorstdev(:, 2)), ...
            distribution_parameters(regioncolorstdev(:, 3)), ...
            distribution_parameters(regiongrayavg), ...
            distribution_parameters(regiongraystdev), ...
            ... %
            gaboravg_avg(1), ...
            gaboravg_avg(2), ...
            gaboravg_avg(3), ...
            gaboravg_avg(4), ...
            gaboravg_avg(5), ...
            gaboravg_avg(6), ...
            gaboravg_avg(7), ...
            gaboravg_avg(8), ...
            ... %
            gaborstd_avg(1), ...
            gaborstd_avg(2), ...
            gaborstd_avg(3), ...
            gaborstd_avg(4), ...
            gaborstd_avg(5), ...
            gaborstd_avg(6), ...
            gaborstd_avg(7), ...
            gaborstd_avg(8), ...
            ... %
            gaboravg_std(1), ...
            gaboravg_std(2), ...
            gaboravg_std(3), ...
            gaboravg_std(4), ...
            gaboravg_std(5), ...
            gaboravg_std(6), ...
            gaboravg_std(7), ...
            gaboravg_std(8), ...
            ... %
            gaborstd_std(1), ...
            gaborstd_std(2), ...
            gaborstd_std(3), ...
            gaborstd_std(4), ...
            gaborstd_std(5), ...
            gaborstd_std(6), ...
            gaborstd_std(7), ...
            gaborstd_std(8), ...
            ... %
            glcm_features(1), ...
            glcm_features(2), ...
            glcm_features(3), ...
            glcm_features(4), ...
            glcm_features(5), ...
            glcm_features(6)];

output_features = {features, ...
                   {... % Labels for features
                    'Area_Avg', ...
                    'Area_Stdev', ...
                    'Area_Median', ...
                    'Area_IQR', ...
                    'Area_Skewness', ...
                    'Area_Kurtosis', ...
                    'Area_Disorder', ...
                    ... %
                    'MajorAxis_Avg', ...
                    'MajorAxis_Stdev', ...
                    'MajorAxis_Median', ...
                    'MajorAxis_IQR', ...
                    'MajorAxis_Skewness', ...
                    'MajorAxis_Kurtosis', ...
                    'MajorAxis_Disorder', ...
                    ... % 
                    'EquivDiam_Avg', ...
                    'EquivDiam_Stdev', ...
                    'EquivDiam_Median', ...
                    'EquivDiam_IQR', ...
                    'EquivDiam_Skewness', ...
                    'EquivDiam_Kurtosis', ...
                    'EquivDiam_Disorder', ...
                    ... % 
                    'Eccentricity_Avg', ...
                    'Eccentricity_Stdev', ...
                    'Eccentricity_Median', ...
                    'Eccentricity_IQR', ...
                    'Eccentricity_Skewness', ...
                    'Eccentricity_Kurtosis', ...
                    'Eccentricity_Disorder', ...
                    ... % 
                    'Solidity_Avg', ...
                    'Solidity_Stdev', ...
                    'Solidity_Median', ...
                    'Solidity_IQR', ...
                    'Solidity_Skewness', ...
                    'Solidity_Kurtosis', ...
                    'Solidity_Disorder', ...
                    ... % 
                    'Compactness_Avg', ...
                    'Compactness_Stdev', ...
                    'Compactness_Median', ...
                    'Compactness_IQR', ...
                    'Compactness_Skewness', ...
                    'Compactness_Kurtosis', ...
                    'Compactness_Disorder', ...
                    ... % 
                    'Crowdedness_Avg', ...
                    'Crowdedness_Stdev', ...
                    'Crowdedness_Median', ...
                    'Crowdedness_IQR', ...
                    'Crowdedness_Skewness', ...
                    'Crowdedness_Kurtosis', ...
                    'Crowdedness_Disorder', ...
                    ... % 
                    'Alignedness_Avg', ...
                    'Alignedness_Stdev', ...
                    'Alignedness_Median', ...
                    'Alignedness_IQR', ...
                    'Alignedness_Skewness', ...
                    'Alignedness_Kurtosis', ...
                    'Alignedness_Disorder', ...
                    ... % 
                    'DelaunayDist_Avg', ...
                    'DelaunayDist_Stdev', ...
                    'DelaunayDist_Median', ...
                    'DelaunayDist_IQR', ...
                    'DelaunayDist_Skewness', ...
                    'DelaunayDist_Kurtosis', ...
                    'DelaunayDist_Disorder', ...
                    ... % 
                    'NormDDMajorAxis_Avg', ...
                    'NormDDMajorAxis_Stdev', ...
                    'NormDDMajorAxis_Median', ...
                    'NormDDMajorAxis_IQR', ...
                    'NormDDMajorAxis_Skewness', ...
                    'NormDDMajorAxis_Kurtosis', ...
                    'NormDDMajorAxis_Disorder', ...
                    ... % 
                    'NormDDEquivDiam_Avg', ...
                    'NormDDEquivDiam_Stdev', ...
                    'NormDDEquivDiam_Median', ...
                    'NormDDEquivDiam_IQR', ...
                    'NormDDEquivDiam_Skewness', ...
                    'NormDDEquivDiam_Kurtosis', ...
                    'NormDDEquivDiam_Disorder', ...
                    ... % 
                    'RegionRedAvg_Avg', ...
                    'RegionRedAvg_Stdev', ...
                    'RegionRedAvg_Median', ...
                    'RegionRedAvg_IQR', ...
                    'RegionRedAvg_Skewness', ...
                    'RegionRedAvg_Kurtosis', ...
                    'RegionRedAvg_Disorder', ...
                    ... % 
                    'RegionGreenAvg_Avg', ...
                    'RegionGreenAvg_Stdev', ...
                    'RegionGreenAvg_Median', ...
                    'RegionGreenAvg_IQR', ...
                    'RegionGreenAvg_Skewness', ...
                    'RegionGreenAvg_Kurtosis', ...
                    'RegionGreenAvg_Disorder', ...
                    ... % 
                    'RegionBlueAvg_Avg', ...
                    'RegionBlueAvg_Stdev', ...
                    'RegionBlueAvg_Median', ...
                    'RegionBlueAvg_IQR', ...
                    'RegionBlueAvg_Skewness', ...
                    'RegionBlueAvg_Kurtosis', ...
                    'RegionBlueAvg_Disorder', ...
                    ... % 
                    'RegionRedStdev_Avg', ...
                    'RegionRedStdev_Stdev', ...
                    'RegionRedStdev_Median', ...
                    'RegionRedStdev_IQR', ...
                    'RegionRedStdev_Skewness', ...
                    'RegionRedStdev_Kurtosis', ...
                    'RegionRedStdev_Disorder', ...
                    ... % 
                    'RegionGreenStdev_Avg', ...
                    'RegionGreenStdev_Stdev', ...
                    'RegionGreenStdev_Median', ...
                    'RegionGreenStdev_IQR', ...
                    'RegionGreenStdev_Skewness', ...
                    'RegionGreenStdev_Kurtosis', ...
                    'RegionGreenStdev_Disorder', ...
                    ... % 
                    'RegionBlueStdev_Avg', ...
                    'RegionBlueStdev_Stdev', ...
                    'RegionBlueStdev_Median', ...
                    'RegionBlueStdev_IQR', ...
                    'RegionBlueStdev_Skewness', ...
                    'RegionBlueStdev_Kurtosis', ...
                    'RegionBlueStdev_Disorder', ...
                    ... % 
                    'RegionGrayAvg_Avg', ...
                    'RegionGrayAvg_Stdev', ...
                    'RegionGrayAvg_Median', ...
                    'RegionGrayAvg_IQR', ...
                    'RegionGrayAvg_Skewness', ...
                    'RegionGrayAvg_Kurtosis', ...
                    'RegionGrayAvg_Disorder', ...
                    ... % 
                    'RegionGrayStdev_Avg', ...
                    'RegionGrayStdev_Stdev', ...
                    'RegionGrayStdev_Median', ...
                    'RegionGrayStdev_IQR', ...
                    'RegionGrayStdev_Skewness', ...
                    'RegionGrayStdev_Kurtosis', ...
                    'RegionGrayStdev_Disorder', ...
                    ... % 
                    'GaborAvg4_Avg', ...
                    'GaborAvg8_Avg', ...
                    'GaborAvg12_Avg', ...
                    'GaborAvg16_Avg', ...
                    'GaborAvg20_Avg', ...
                    'GaborAvg24_Avg', ...
                    'GaborAvg28_Avg', ...
                    'GaborAvg32_Avg', ...
                    ... % 
                    'GaborStd4_Avg', ...
                    'GaborStd8_Avg', ...
                    'GaborStd12_Avg', ...
                    'GaborStd16_Avg', ...
                    'GaborStd20_Avg', ...
                    'GaborStd24_Avg', ...
                    'GaborStd28_Avg', ...
                    'GaborStd32_Avg', ...
                    ... % 
                    'GaborAvg4_Std', ...
                    'GaborAvg8_Std', ...
                    'GaborAvg12_Std', ...
                    'GaborAvg16_Std', ...
                    'GaborAvg20_Std', ...
                    'GaborAvg24_Std', ...
                    'GaborAvg28_Std', ...
                    'GaborAvg32_Std', ...
                    ... % 
                    'GaborStd4_Std', ...
                    'GaborStd8_Std', ...
                    'GaborStd12_Std', ...
                    'GaborStd16_Std', ...
                    'GaborStd20_Std', ...
                    'GaborStd24_Std', ...
                    'GaborStd28_Std', ...
                    'GaborStd32_Std', ...
                    ... %
                    'Haralick_AngSecMoment', ...
                    'Haralick_InvDiffMoment', ...
                    'Haralick_Contrast', ...
                    'Haralick_Correlation', ...
                    'Haralick_Entropy', ...
                    'Haralick_SumAvg'}};

end