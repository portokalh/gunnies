function [ out ] = par_NN_Label_Regularization( NN_labels, interpolated_labels) % , w, xmin, xmax, ymin, ymax, zmin, zmax)

% Parallelized 

    [path,file,~] = fileparts(interpolated_labels);

    out = [path '/' file '_corrected.nii'];

    data = load_nii(NN_labels);
    NN_data = double(data.img);

    data = load_nii(interpolated_labels);
    Interp_data = double(data.img);

    Output = NN_data;

    % size = w*2+1;
    
    w = 1;
    wsize = 3;
    
%     x = xmax-xmin+1;
%     y = ymax-ymin+1;
%     z = zmax-zmin+1;

    [x y z] = size(Interp_data);
    
    xmin = 1 + w;
    ymin = 1 + w;
    zmin = 1 + w;
    xmax = x - w;
    ymax = y - w;
    zmax = z - w;
    
    x = numel(xmin:xmax);
    y = numel(ymin:ymax);
    z = numel(zmin:zmax);

    % Create packets
    packets = zeros(wsize, wsize, wsize, x, y, z);

    for i = xmin:xmax % rows
        for j = ymin:ymax % columns
            for b = zmin:zmax

                imin = i-w; imax = i+w; jmin = j-w; jmax = j+w; bmin = b-w; bmax = b+w;

                packets(:,:,:,(i-(xmin-1)),(j-(ymin-1)),(b-(zmin-1))) = NN_data(imin:imax,jmin:jmax,bmin:bmax);

            end
        end
    end
    
    packets = reshape(packets, [wsize wsize wsize (x*y*z)]);
    Interp_data_mid = reshape(Interp_data(xmin:xmax, ymin:ymax, zmin:zmax), [(x*y*z) 1]);
    Output_mid = reshape(Output(xmin:xmax, ymin:ymax, zmin:zmax), [(x*y*z) 1]);

    parfor g = 1:(x*y*z) % packets

        I = packets(:,:,:,g);

        vals = unique(I);

        if numel(vals) > 1

            current = Interp_data_mid(g);

            min_val = 100;
            min_diff = 100;

            for k = 1:numel(vals)

                difference = abs(current - vals(k));

                if difference < min_diff

                    min_val = vals(k);
                    min_diff = difference;

                end

            end

            Output_mid(g) = min_val;

        end

    end

    Output(xmin:xmax, ymin:ymax, zmin:zmax) = reshape(Output_mid, [x y z]);

    B = make_nii(Output, [0.088 0.088 0.088], [-0.088 -0.088 0.088], 16);
    save_nii(B, out);
    copy_header(NN_labels,out);
end