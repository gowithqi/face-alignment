function Te_Data = globalprediction(binaryfeatures, W, Te_Data, params, stage)
%GLOBALREGRESSION Summary of this function goes here
%   Function: implement global regression given binary features and
%   groundtruth shape
%   Detailed explanation goes here
%   Input:
%        binaryfeatures: extracted binary features from all samples (N X d  )
%        Te_Data: test data
%        params: parameters for model
%   Output:
%        W: regression matrix

% organize the groundtruth shape
dbsize      = length(Te_Data);
gtshapes = zeros([size(params.meanshape) dbsize*(params.augnumber)]);  % concatenate 2-D coordinates into a vector (N X (2*L))
dist_pupils = zeros(dbsize*(params.augnumber), 1);

for i = 1:dbsize*(params.augnumber)
    k = floor((i-1)/(params.augnumber)) + 1;
    s = mod(i-1, (params.augnumber)) + 1;    
    shape_gt = Te_Data{k}.shape_gt;
    gtshapes(:, :, i) = reshape(shape_gt(:), size(params.meanshape));
    
    % left eye: 37-42
    % right eye: 43-48
    if size(shape_gt, 1) == 68
        dist_pupils(i) = norm((mean(shape_gt(37:42, :)) - mean(shape_gt(43:48, :))));
    elseif size(shape_gt, 1) == 29
        dist_pupils(i) = norm((mean(shape_gt(9:2:17, :)) - mean(shape_gt(10:2:18, :))));        
    end
    
end

% Predict the location of lanmarks using current regression matrix
disp(size(binaryfeatures));
disp(size(W));
deltashapes_bar = binaryfeatures*W;

predshapes = zeros([size(params.meanshape) dbsize*(params.augnumber)]);  % concatenate 2-D coordinates into a vector (N X (2*L))

for i = 1:dbsize*(params.augnumber)
    k = floor((i-1)/(params.augnumber)) + 1;
    s = mod(i-1, (params.augnumber)) + 1;
    
    shapes_stage = Te_Data{k}.intermediate_shapes{stage};
    shape_stage = shapes_stage(:, :, s);
    
    deltashapes_bar_xy = reshape(deltashapes_bar(i, :), [uint8(size(deltashapes_bar, 2)/2) 2]);

    % transform above delta shape into the coordinate of current intermmediate shape
    delta_shape_intermmed_coord = tforminv(Te_Data{k}.tf2meanshape{s}, deltashapes_bar_xy(:, 1), deltashapes_bar_xy(:, 2));
    
    delta_shape_meanshape_coord = bsxfun(@times, delta_shape_intermmed_coord, Te_Data{k}.intermediate_bboxes{stage}(s, 3:4));
    
        
    shape_newstage = shape_stage + delta_shape_meanshape_coord;        
    
    predshapes(:, :, i) = reshape(shape_newstage(:), size(params.meanshape));
    
    Te_Data{k}.intermediate_shapes{stage+1}(:, :, s) = shape_newstage;
    Te_Data{k}.intermediate_bboxes{stage+1}(s, :)    = Te_Data{k}.intermediate_bboxes{stage}(s, :); % getbbox(shape_newstage);
    
    % update transformation of current intermediate shape to meanshape
    meanshape_resize = resetshape(Te_Data{k}.intermediate_bboxes{stage+1}(s, :) , params.meanshape);        
    Te_Data{k}.tf2meanshape{s} = cp2tform(bsxfun(@minus, Te_Data{k}.intermediate_shapes{stage+1}(:,:, s), mean(Te_Data{k}.intermediate_shapes{stage+1}(:,:, s))), ...
        bsxfun(@minus, meanshape_resize(:, :), mean(meanshape_resize(:, :))), 'nonreflective similarity');
    
    
    if stage >= params.max_numstage 
        % [Te_Data{k}.shape_gt Te_Data{k}.intermediate_shapes{1}(:,:, s) shape_newstage]
        
        if params.show_debug_image == 1
            drawshapes(Te_Data{k}.img_gray, [Te_Data{k}.shape_gt Te_Data{k}.intermediate_shapes{1}(:,:, s) shape_newstage]);       
            hold off;
            drawnow;
            w = waitforbuttonpress;
        end
    end
    
end

error_per_image = compute_error(gtshapes, predshapes);

MRSE = 100*mean(error_per_image);
MRSE_display = sprintf('Stage %d: Mean Root Square Error for %d Test Samples: %f', stage, (dbsize*(params.augnumber)), MRSE);
disp(MRSE_display);

end

function [ error_per_image ] = compute_error( ground_truth_all, detected_points_all )
%compute_error
%   compute the average point-to-point Euclidean error normalized by the
%   inter-ocular distance (measured as the Euclidean distance between the
%   outer corners of the eyes)
%
%   Inputs:
%          grounth_truth_all, size: num_of_points x 2 x num_of_images
%          detected_points_all, size: num_of_points x 2 x num_of_images
%   Output:
%          error_per_image, size: num_of_images x 1


num_of_images = size(ground_truth_all,3);
num_of_points = size(ground_truth_all,1);

error_per_image = zeros(num_of_images,1);

for i =1:num_of_images
    detected_points      = detected_points_all(:,:,i);
    ground_truth_points  = ground_truth_all(:,:,i);
    if num_of_points == 68
        interocular_distance = norm(mean(ground_truth_points(37:42,:))-mean(ground_truth_points(43:48,:)));  % norm((mean(shape_gt(37:42, :)) - mean(shape_gt(43:48, :))));
    elseif num_of_points == 51
        interocular_distance = norm(ground_truth_points(20,:)-ground_truth_points(29,:));
    elseif num_of_points == 29
        interocular_distance = norm(mean(ground_truth_points(9:2:17,:))-mean(ground_truth_points(10:2:18,:)));        
    end
    
    sum=0;
    for j=1:num_of_points
        sum = sum+norm(detected_points(j,:)-ground_truth_points(j,:));
    end
    error_per_image(i) = sum/(num_of_points*interocular_distance);
end

end

